using System;
using System.IO;
using BeefYield;
using BeefParser;
using BeefParser.AST;
using System.Diagnostics;
using System.Collections;

namespace BeefYield.Tests
{
	struct DisposableLogger : IDisposable
	{
		private List<String> mLog;
		private int mId;

		public this(int id, List<String> log)
		{
			mId = id;
			mLog = log;
			mLog.Add(new $"[Dispose] Created {mId}");
		}

		public void Dispose()
		{
			mLog.Add(new $"[Dispose] Disposed {mId}");
		}
	}

	class Test5
	{
		// TODO: Use something like Compiler.CalledFilePath instead.
		const String FilePath = @"d:\BeefLang\Repository\BeefYield\Tests\src\Test5.bf";

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<int> ComplexYieldMachine(List<String> log)
		{
#unwarn
			log.Add(new $"Machine Start");
			defer { log.Add(new $"Defer Root"); }

			for (int i = 0; i < 5; i++)
			{
				log.Add(new $"Loop Start {i}");
				defer { log.Add(new $"Defer Loop {i}"); }

				using (DisposableLogger(i, log))
				{
					if (i < 2)
					{
						log.Add(new $"If Block {i}");
						defer { log.Add(new $"Defer If {i}"); }

						YieldReturn!(i);

						if (i == 1)
						{
							log.Add(new $"Continue");
							continue;
						}

						YieldReturn!(i + 10);
					}
					else
					{
						log.Add(new $"Else Block {i}");
						if (i == 3)
						{
							log.Add(new $"YieldBreak");
							YieldBreak!();
						}
						YieldReturn!(i * 100);
					}
				}

				log.Add(new $"Loop End {i}");
			}

			log.Add(new $"Machine End");
		}

		[Test]
		public static void Test5()
		{
			let log = scope List<String>();
			let yieldedValues = scope List<int>();

			for (let val in ComplexYieldMachine(log))
			{
				log.Add(new $"Yielded {val}");
				yieldedValues.Add(val);
			}

			let expectedValues = scope int[]( 0, 10, 1, 200 );
			Test.Assert(yieldedValues.Count == expectedValues.Count);
			for (int i = 0; i < expectedValues.Count; i++)
			{
				Test.Assert(yieldedValues[i] == expectedValues[i]);
			}

			let expectedLog = scope String[] (
				"Machine Start",

				"Loop Start 0",
				"[Dispose] Created 0",
				"If Block 0",
				"Yielded 0",
				"Yielded 10",
				"Defer If 0",
				"[Dispose] Disposed 0",
				"Loop End 0",
				"Defer Loop 0",

				"Loop Start 1",
				"[Dispose] Created 1",
				"If Block 1",
				"Yielded 1",
				"Continue",
				"Defer If 1",
				"[Dispose] Disposed 1",
				"Defer Loop 1",

				"Loop Start 2",
				"[Dispose] Created 2",
				"Else Block 2",
				"Yielded 200",
				"[Dispose] Disposed 2",
				"Loop End 2",
				"Defer Loop 2",

				"Loop Start 3",
				"[Dispose] Created 3",
				"Else Block 3",
				"YieldBreak",
				"[Dispose] Disposed 3",
				"Defer Loop 3",

				"Defer Root"
			);

			for (int i = 0; i < expectedLog.Count; i++)
			{
				if (log[i] != expectedLog[i])
				{
					Debug.WriteLine("Log mismatch at index {}:", i);
					Debug.WriteLine("  Expected: {}", expectedLog[i]);
					Debug.WriteLine("  Got:      {}", log[i]);
					Test.Assert(false);
				}
			}
			Test.Assert(log.Count == expectedLog.Count, scope $"Log count mismatch. Expected {expectedLog.Count}, got {log.Count}");

			Release!(log, ContainerReleaseKind.Items);
			GC.Collect(false);
		}
	}
}