using System;
using BeefYield;
using System.Collections;

namespace BeefYield.Tests
{
	class Test6
	{
		// TODO: Use something like Compiler.CalledFilePath instead.
		const String FilePath = @"d:\BeefLang\Repository\BeefYield\Tests\src\Test6.bf";

		public enum TestAction
		{
			case SimpleOk(int res),
			OkAndContinue(int res),
			OkAndBreak(int res),
			Nested(Result<int, String> res),
			NoOp;
		}

		[MakeYieldable(FilePath)]
		public static YieldEnumerator<int> ComplexYieldWithPayloads(List<TestAction> actions)
		{
#unwarn
			YieldReturn!(-1);

			for (TestAction action in actions)
			{
				switch (action)
				{
					case .SimpleOk(let value):
						YieldReturn!(value);
						break;

					case .OkAndContinue(let value):
						YieldReturn!(value);
						continue;

					case .OkAndBreak(let value):
						YieldReturn!(value);
						YieldBreak!();

					case .Nested(let innerResult):
						if (innerResult case .Ok(let nestedValue))
							YieldReturn!(nestedValue);
						break;

					case .NoOp:
						NOP!(); //fallthrough;

					default:
						break;
				}

				YieldReturn!(-99);
			}

			YieldReturn!(-2);
		}

		[Test]
		public static void TestComplexPayloadPatternMatch()
		{
			let actions = scope List<TestAction>()
			{
				.SimpleOk(100),
				.Nested(.Err(scope $"Inner Err")),
				.OkAndContinue(200),
				.Nested(.Ok(400)),
				.NoOp,
				.OkAndBreak(300),
				.SimpleOk(999)
			};

			let yieldedValues = scope List<int>();
			for (let val in ComplexYieldWithPayloads(actions))
			{
				yieldedValues.Add(val);
			}

			let expectedValues = scope int[](
				-1,
				100,
				-99,
				-99,
				200,
				400,
				-99,
				-99,
				300
			);

			Test.Assert(yieldedValues.Count == expectedValues.Count,
				scope $"Incorrect number of yielded values. Expected {expectedValues.Count}, got {yieldedValues.Count}.");

			for (int i = 0; i < expectedValues.Count; i++)
			{
				Test.Assert(yieldedValues[i] == expectedValues[i],
					scope $"Value mismatch at index {i}. Expected {expectedValues[i]}, got {yieldedValues[i]}.");
			}

			GC.Collect(false);
		}
	}
}