using System;
using System.IO;
using BeefYield;
using BeefParser;
using BeefParser.AST;
using System.Diagnostics;

namespace BeefYield.Tests
{
	class Test1
	{
		// TODO: Use something like Compiler.CalledFilePath instead.
		const String FilePath = @"d:\BeefLang\Repository\BeefYield\Tests\src\Test4.bf";

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<int> Yieldable(int n)
		{
#unwarn
			if (n <= 1)
				YieldReturn!(n);
	
			int t1 = 0, t2 = 1, nextTerm = t1 + t2;
			while (nextTerm <= n)
			{
				YieldReturn!(nextTerm);
				defer {t1 = t2;}
				defer {t2 = nextTerm;}
				defer {nextTerm = t1 + t2;}
				if (n == 2)
					break;
			}
		}
	
		[Test]
		public static void Test2()
		{
			int final = 0;
			for (let i in Yieldable(100))
			{
				Debug.WriteLine("Fib: {}", i);
				final = i;
			}

			Test.Assert(final == 89);
			GC.Collect(false);
		}
	}
}