using System;
using System.Collections;
using BeefYield;

namespace BeefYield.Tests
{
	struct TestDisposer : IDisposable
	{
		public static int sCount;
		public int mVal;
		public this(int v) { mVal = v; }
		public void Dispose() { sCount += mVal; }
	}

	class LoopFinalizersTest
	{
		// TODO: Use something like Compiler.CalledFilePath instead.
		const String FilePath = @"d:\BeefLang\Repository\BeefYield\Tests\src\LoopFinalizersTest.bf";

		public static void ExpectArrayEq(Span<int> actual, Span<int> expected)
		{
			Test.Assert(actual.Length == expected.Length,
				scope $"Array length mismatch: got {actual.Length}, expected {expected.Length}");

			for (int i = 0; i < actual.Length; i++)
			{
				Test.Assert(actual[i] == expected[i],
					scope $"Array element {i} mismatch: got {actual[i]}, expected {expected[i]}");
			}
		}

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<int> UsingInLoops()
		{
#unwarn
			TestDisposer.sCount = 0;

			for (int i = 1; i <= 2; i++)
			{
				using (var d = TestDisposer(i))
				{
					YieldReturn!(10 * i);
					if (i == 1)
						continue;
					YieldReturn!(100 * i);
				}
			}

			YieldReturn!(TestDisposer.sCount);
		}

		[Test]
		public static void UsingWithContinueAndFallOff()
		{
			let res = scope List<int>();
			for (let v in UsingInLoops())
				res.Add(v);

			ExpectArrayEq(res, scope int[](10, 20, 200, 3));
			GC.Collect(false);
		}

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<int> UsingBreakDisposes()
		{
#unwarn
			TestDisposer.sCount = 0;
			for (int j = 1; j <= 3; j++)
			{
				if (j == 2)
				{
					using (var d = TestDisposer(10))
					{
						break;
					}
				}
			}
			YieldReturn!(TestDisposer.sCount);
		}

		[Test]
		public static void UsingBreak()
		{
			let res = scope List<int>();
			for (let v in UsingBreakDisposes())
				res.Add(v);
			ExpectArrayEq(res, scope int[](10));
			GC.Collect(false);
		}

		static List<int> sLog = new .() ~ delete _;

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<int> DeferOnContinueAndBreak()
		{
#unwarn
			sLog.Clear();

			for (int i = 0; i < 2; i++)
			{
				defer
				{
					sLog.Add(100 + i);
				}

				YieldReturn!(i);

				if (i == 1)
					break;
				continue;
			}

			for (int k = 0; k < sLog.Count; k++)
				YieldReturn!(sLog[k]);
		}

		[Test]
		public static void DeferOrdering()
		{
			let res = scope List<int>();
			for (let v in DeferOnContinueAndBreak())
				res.Add(v);

			ExpectArrayEq(res, scope int[](0, 1, 100, 101));
			GC.Collect(false);
		}
	}
}