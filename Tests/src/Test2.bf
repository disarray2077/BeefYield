using System;
using BeefYield;
using System.Diagnostics;
using System.Collections;

namespace BeefYield.Tests
{
	class Test2
	{
		// TODO: Use something like Compiler.CalledFilePath instead.
		const String FilePath = @"d:\BeefLang\Repository\BeefYield\Tests\src\Test2.bf";

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<char8> Yieldable(String str)
		{
#unwarn
			for (int j = 0; j < 2; j++)
			{
				Debug.WriteLine("Start");
				for (int i = 0; i < str.Length; i++)
				{
					YieldReturn!(str[i]);
				}
				Debug.WriteLine("End");
			}
		}
	
		[Test]
		public static void Test2()
		{
			int count = 0;
			for (let i in Yieldable("Beef"))
			{
				Debug.WriteLine("Char: {}", i);
				count++;
			}
			Test.Assert(count == 8);
			GC.Collect(false);
		}
	}
}