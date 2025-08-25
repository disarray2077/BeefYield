using System;
using System.Collections;
using BeefYield;

namespace BeefYield.Tests
{
	class LabeledControlFlowTest
	{
		// TODO: Use something like Compiler.CalledFilePath instead.
		const String FilePath = @"d:\BeefLang\Repository\BeefYield\Tests\src\LabeledControlFlowTest.bf";

		[MakeYieldable(FilePath)]
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