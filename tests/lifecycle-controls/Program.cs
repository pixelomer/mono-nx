using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

static class Controls
{
    [DllImport("lifecycle")] static extern void lifecycle_log(string text);
    [DllImport("lifecycle")] static extern ulong lifecycle_native_used();
    [ThreadStatic] static int identity;
    static int alive, errors, caught;
    const int Workers = 8, Iterations = 128, Rounds = 48;

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void Throw() => throw new InvalidOperationException("lifecycle control");

    static void Worker(int mode, int token)
    {
        try
        {
            if (identity != 0) Interlocked.Increment(ref errors);
            identity = token;
            for (int i = 0; i < Iterations; i++)
            {
                if (mode == 1)
                {
                    var data = new byte[16384];
                    data[0] = (byte)i;
                    data[^1] = (byte)(i ^ token);
                    Thread.Yield();
                    if (data[0] != (byte)i || data[^1] != (byte)(i ^ token))
                        Interlocked.Increment(ref errors);
                    GC.KeepAlive(data);
                }
                if (mode >= 2)
                {
                    bool completedFinally = false;
                    try { Throw(); }
                    catch (InvalidOperationException) { Interlocked.Increment(ref caught); }
                    finally { completedFinally = true; }
                    if (!completedFinally) Interlocked.Increment(ref errors);
                }
                if (identity != token) Interlocked.Increment(ref errors);
            }
        }
        catch (Exception ex)
        {
            Interlocked.Increment(ref errors);
            lifecycle_log("WORKER FAILED: " + ex.GetType().FullName);
        }
        finally { Interlocked.Decrement(ref alive); }
    }

    // End this scope before post-round collection so local Thread references
    // cannot accidentally keep the previous round's managed handles alive.
    [MethodImpl(MethodImplOptions.NoInlining)]
    static void Round(int mode, int round)
    {
        alive = Workers;
        if (mode == 3)
        {
            for (int i = 0; i < Workers; i++)
            {
                identity = 0;
                Worker(mode, round * Workers + i + 1);
            }
            identity = 0;
            return;
        }
        var threads = new Thread[Workers];
        for (int i = 0; i < Workers; i++)
        {
            int token = round * Workers + i + 1;
            threads[i] = new Thread(() => Worker(mode, token));
            threads[i].Start();
        }
        while (Volatile.Read(ref alive) != 0)
        {
            GC.Collect(2, GCCollectionMode.Forced, true, true);
            Thread.Sleep(1);
        }
        foreach (var thread in threads) thread.Join();
    }

    public static void Main()
    {
        lifecycle_log("BEGIN Mono LLVM lifecycle controls; runtime=" + Environment.Version);
        string[] phases = { "threads-only", "threads-alloc", "threads-eh", "main-eh" };
        for (int mode = 0; mode < phases.Length; mode++)
        {
            caught = 0;
            for (int round = 0; round < Rounds; round++)
            {
                Round(mode, round);
                GC.Collect(2, GCCollectionMode.Forced, true, true);
                GC.WaitForPendingFinalizers();
                GC.Collect(2, GCCollectionMode.Forced, true, true);
                Thread.Sleep(100);
                int expected = mode >= 2 ? (round + 1) * Workers * Iterations : 0;
                if (identity != 0 || caught != expected || alive != 0) errors++;
                ulong native = lifecycle_native_used();
                lifecycle_log($"phase={phases[mode]} round={round} native_used={native} managed_live={GC.GetTotalMemory(false)} caught={caught} errors={errors}");
                if (errors != 0) { lifecycle_log("FAIL"); return; }
            }
        }
        lifecycle_log("PASS phases=4 rounds_per_phase=48 joined_workers=1152 explicit_exceptions=98304 array_payload_bytes=805306368");
    }
}
