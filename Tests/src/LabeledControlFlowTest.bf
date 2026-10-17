using System;
using System.Collections;
using BeefYield;

namespace BeefYield.Tests
{
	class LabeledControlFlowTest
	{
		[MakeYieldable]
		public static YieldEnumerator<int> BreakAcrossSwitchWithDefers(List<int> log)
		{
#unwarn
			defer { log.Add(0); }
			outer: while (true)
			{
				defer { log.Add(1); }
				YieldReturn!(0);
				switch (0)
				{
				case 0:
					defer { log.Add(2); }
					break outer;
				}
			}
			YieldReturn!(42);
		}

		[MakeYieldable]
		public static YieldEnumerator<int> ContinueAcrossLoopWithDefers(List<int> log)
		{
#unwarn
			defer { log.Add(0); }
			outer: for (int i = 0; i < 2; i++)
			{
				defer { log.Add(10 + i); }
				for (int j = 0; j < 2; j++)
				{
					defer { log.Add(20); }
					YieldReturn!(i * 10 + j);
					if (j >= 0)
						continue outer;
				}
			}
		}

		[Test]
		public static void LabeledBreakUnwindsPastSwitch()
		{
			let log = scope List<int>();
			let values = scope List<int>();
			for (let value in BreakAcrossSwitchWithDefers(log))
				values.Add(value);
			ExpectArrayEq(values, scope int[](0, 42));
			ExpectArrayEq(log, scope int[](2, 1, 0));
		}

		[Test]
		public static void LabeledContinueUnwindsExitedLoops()
		{
			let log = scope List<int>();
			let values = scope List<int>();
			for (let value in ContinueAcrossLoopWithDefers(log))
				values.Add(value);
			ExpectArrayEq(values, scope int[](0, 10));
			ExpectArrayEq(log, scope int[](20, 10, 20, 11, 0));
		}

		[MakeYieldable]
		public static YieldEnumerator<int> LabeledContinueOuter()
		{
#unwarn
			outer:
			for (int i = 0; i < 2; i++)
			{
				for (int j = 0; j < 2; j++)
				{
					YieldReturn!(i * 10 + j);
					if (j == 0)
						continue outer; // jump to next 'i'
				}
				// never reached because j==0 always continues 'outer'
				YieldReturn!(-i);
			}
			YieldReturn!(999);
		}

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

		[Test]
		public static void LabeledContinue()
		{
			let res = scope List<int>();
			for (let v in LabeledContinueOuter())
				res.Add(v);

			ExpectArrayEq(res, scope int[](0, 10, 999));
			GC.Collect(false);
		}
	}
}
