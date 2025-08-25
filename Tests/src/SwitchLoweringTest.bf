using System;
using System.Collections;
using BeefYield;

namespace BeefYield.Tests
{
	class SwitchLoweringTest
	{
		// TODO: Use something like Compiler.CalledFilePath instead.
		const String FilePath = @"d:\BeefLang\Repository\BeefYield\Tests\src\SwitchLoweringTest.bf";

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
		public static YieldEnumerator<int> SwitchDefaultOnly(int x)
		{
#unwarn
			switch (x)
			{
			default:
				YieldReturn!(x);
				break;
			}
			YieldReturn!(999);
		}

		[Test]
		public static void DefaultOnly()
		{
			let res = scope List<int>();
			for (let v in SwitchDefaultOnly(42))
				res.Add(v);
			ExpectArrayEq(res, scope int[](42, 999));
			GC.Collect(false);
		}

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<int> SwitchWithWhen(int x, int y = 0)
		{
#unwarn
			switch (x)
			{
			case 1, 3:
				YieldReturn!(13);
				break;

			case 2 when y > 0 && (y % 2) == 0:
				YieldReturn!(y);
				break;

			default:
				YieldReturn!(0);
				break;
			}
			YieldReturn!(99);
		}

		[Test]
		public static void WithWhen()
		{
			let a = scope List<int>();
			for (let v in SwitchWithWhen(1)) a.Add(v);
			ExpectArrayEq(a, scope int[](13, 99));

			let b = scope List<int>();
			for (let v in SwitchWithWhen(2)) b.Add(v);
			ExpectArrayEq(b, scope int[](0, 99));

			let b = scope List<int>();
			for (let v in SwitchWithWhen(2, 20)) b.Add(v);
			ExpectArrayEq(b, scope int[](20, 99));

			let c = scope List<int>();
			for (let v in SwitchWithWhen(4)) c.Add(v);
			ExpectArrayEq(c, scope int[](0, 99));

			GC.Collect(false);
		}
	}
}