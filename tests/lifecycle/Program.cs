using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

static class Lifecycle
{
    [DllImport("lifecycle")] static extern void lifecycle_log(string text);
    [DllImport("lifecycle")] static extern ulong lifecycle_native_used();
    [ThreadStatic] static int identity;
    static int alive, errors, caught, finalized;
    const int Workers = 8, Iterations = 128, Rounds = 20;

    sealed class Finalizable
    {
        ~Finalizable() => Interlocked.Increment(ref finalized);
    }
    [MethodImpl(MethodImplOptions.NoInlining)]
    static void MakeFinalizable() { _ = new Finalizable(); }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void Throw() => throw new InvalidOperationException("lifecycle test");

    static void Worker(int token)
    {
        try
        {
            if (identity != 0) Interlocked.Increment(ref errors);
            identity = token;
            var kept = new byte[16384];
            kept[0] = (byte)token;
            for (int i = 0; i < Iterations; i++)
            {
                var data = new byte[16384];
                data[0] = (byte)i;
                data[^1] = (byte)(i ^ token);
                bool completedFinally = false;
                try { Throw(); }
                catch (InvalidOperationException) { Interlocked.Increment(ref caught); }
                finally { completedFinally = true; }
                if (!completedFinally || identity != token || kept[0] != (byte)token ||
                    data[0] != (byte)i || data[^1] != (byte)(i ^ token))
                    Interlocked.Increment(ref errors);
                if ((i & 15) == 0) Thread.Yield();
            }
            MakeFinalizable();
            GC.KeepAlive(kept);
        }
        catch (Exception ex)
        {
            Interlocked.Increment(ref errors);
            lifecycle_log("WORKER FAILED: " + ex.GetType().FullName);
        }
        finally { Interlocked.Decrement(ref alive); }
    }

    public static void Main()
    {
        lifecycle_log("BEGIN Mono LLVM lifecycle: explicit EH, GC, TLS, joined threads");
        lifecycle_log("runtime=" + Environment.Version);
        for (int round = 0; round < Rounds; round++)
        {
            alive = Workers;
            var threads = new Thread[Workers];
            for (int i = 0; i < Workers; i++)
            {
                int token = round * Workers + i + 1;
                threads[i] = new Thread(() => Worker(token));
                threads[i].Start();
            }
            int collections = 0;
            while (Volatile.Read(ref alive) != 0)
            {
                GC.Collect(2, GCCollectionMode.Forced, true, true);
                collections++;
                Thread.Sleep(1);
            }
            foreach (var thread in threads) thread.Join();
            GC.Collect(2, GCCollectionMode.Forced, true, true);
            GC.WaitForPendingFinalizers();
            GC.Collect(2, GCCollectionMode.Forced, true, true);
            Thread.Sleep(100); // Let Mono's native join registry drain.
            if (identity != 0 || caught != (round + 1) * Workers * Iterations ||
                finalized != (round + 1) * Workers) errors++;
            ulong native = lifecycle_native_used();
            lifecycle_log($"round={round} native_used={native} managed_live={GC.GetTotalMemory(false)} collections={collections} caught={caught} finalized={finalized} errors={errors}");
            if (errors != 0) { lifecycle_log("FAIL"); return; }
        }
        lifecycle_log("PASS rounds=20 joined_workers=160 explicit_exceptions=20480 finalizers=160 payload_bytes=335544320");
    }
}
