using System;
using System.IO;
using BeefYield;
using BeefParser;
using BeefParser.AST;
using System.Diagnostics;
using System.Collections;

namespace BeefYield.Tests
{
	class IfLoweringTest
	{
		// TODO: Use something like Compiler.CalledFilePath instead.
		const String FilePath = @"d:\BeefLang\Repository\BeefYield\Tests\src\IfLoweringTest.bf";

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<int> Branchy(int mode)
		{
#unwarn
			int flag = 0;

			if (mode >= 7)
			{
				if (mode == 7)
				{
					YieldReturn!(70);
				}
				else if (mode == 9)
				{
					outerLoop: while (true)
					{
						switch (mode)
						{
						case 9:
							Test.Assert(flag == 0);
							flag += 2;
							if (mode == 9)
							{
								break outerLoop;
							}
							flag += 2;

						case 2:
							YieldBreak!();
						}
					}
				}
				else
				{
					flag = 1;
				}

				flag += 1;
			}

			if (mode == 0)
			{
				flag = 2;
			}
			else if (mode == 1)
			{
				YieldBreak!();
			}
			else if (mode == 2)
			{
				flag = 3;
			}
			else if (mode == 3)
			{
				YieldReturn!(30);
			}
			else if (mode == 4)
			{
				YieldReturn!(40);
			}
			else
			{
				if (flag == 0)
					flag = 4;
			}

			if (mode == 2)
			{
				YieldReturn!(20);
			}
			else if (mode == 0 || mode == 1)
			{
				flag += 1;
			}
			else if (mode == 4)
			{
				YieldReturn!(41);
			}

			if (mode == 6)
				YieldReturn!(60);

			if (flag != 0)
				YieldReturn!(70 + flag);

			YieldReturn!(999);
		}

		public static void Run(int mode, List<int> res)
		{
			for (let v in Branchy(mode))
				res.Add(v);
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
		public static void CoverAllIfPaths()
		{
			ExpectArrayEq(Run(0, .. scope .()), scope int[] ( 73, 999      ));
			ExpectArrayEq(Run(1, .. scope .()), scope int[] (              ));
			ExpectArrayEq(Run(2, .. scope .()), scope int[] ( 20, 73, 999  ));
			ExpectArrayEq(Run(3, .. scope .()), scope int[] ( 30, 999      ));
			ExpectArrayEq(Run(4, .. scope .()), scope int[] ( 40, 41, 999  ));
			ExpectArrayEq(Run(5, .. scope .()), scope int[] ( 74, 999      ));
			ExpectArrayEq(Run(6, .. scope .()), scope int[] ( 60, 74, 999  ));
			ExpectArrayEq(Run(7, .. scope .()), scope int[] ( 70, 71, 999  ));
			ExpectArrayEq(Run(8, .. scope .()), scope int[] ( 72, 999      ));
			ExpectArrayEq(Run(9, .. scope .()), scope int[] ( 73, 999      ));

			GC.Collect(false);
		}
	}
}