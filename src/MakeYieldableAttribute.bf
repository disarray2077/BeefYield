using System;
using System.Reflection;
using System.Diagnostics;
using System.IO;
using BeefParser;
using BeefParser.AST;

namespace BeefYield;

[AttributeUsage(.Method)]
struct MakeYieldableAttribute : Attribute, IOnMethodInit
{
	public String mFilePath;

	public this(String filePath)
	{
		mFilePath = filePath;
	}

	[Comptime]
	public void OnMethodInit(MethodInfo methodInfo, Self* prev)
	{
		StringView methodName = methodInfo.Name;

		Type retType = methodInfo.ReturnType;
		Type yieldType = null;
		if (var specializedGeneric = retType as SpecializedGenericType)
			yieldType = specializedGeneric.GetGenericArg(0);

		if (yieldType == null)
			return;

		String text = scope .();
		File.ReadAllText(mFilePath, text);

		BeefParser parser = scope BeefParser(text);

		CompilationUnit root;
		parser.Parse(out root);

		let methodDecl = findMethod(root, methodName);
		
		let frameGen = new FrameGenVisitor();
		frameGen.Visit(methodDecl.CompoundStmt);
		
		let finalCode = scope String();
		generateFinalCode(frameGen, yieldType, finalCode);
		Compiler.EmitMethodEntry(methodInfo, finalCode);
	}

	protected MethodDecl findMethod(CompilationUnit root, StringView methodName)
	{
		FindMethodVisitor visitor = scope .(methodName);
		visitor.Visit(root);
		Runtime.Assert(visitor.FoundMethod != null);
		return visitor.FoundMethod;
	}

	protected void generateFinalCode(FrameGenVisitor frameGen, Type yieldType, String output)
	{
		output.AppendF(
			$$"""
			{
			[Inline] static __T __GetEnumerator<__T, __U>(__T obj) where __T : System.Collections.IEnumerator<__U> => obj;
			[Inline] static decltype(default(__T).GetEnumerator()) __GetEnumerator<__T, __U>(__T obj) where __T : System.Collections.IEnumerable<__U> => obj.GetEnumerator();
			{{generateContextTuple(frameGen, .. scope .())}}
			return YieldEnumerator<comptype({{yieldType.GetTypeId()}})>()..Set(TContext, (state, context) => {
				static mixin CheckTypeNoWarn<T>(var obj) => obj is T;
			{{generateVarsAssign(frameGen, .. scope .())}}
				while(true)
				{
					switch (state)
					{
			{{generateSwitchCases(frameGen, .. scope .())}}
					default:
					Runtime.FatalError();
					}
				}
			});
			}
			""");
	}

	protected void generateContextTuple(FrameGenVisitor frameGen, String output)
	{
		for (let variable in frameGen.Variables)
		{
			output.AppendF($"{variable.value} {variable.key} = ?;\n");
		}

		if (frameGen.Variables.IsEmpty)
		{
			output.Append("#unwarn\nvoid TContext = ?;");
			return;
		}

		output.Append("(");

		bool first = true;
		for (let variable in frameGen.Variables)
		{
			if (!first)
				output.Append(", ");
			output.AppendF($"decltype({variable.key}) m_{variable.key}");
			first = false;
		}

		if (frameGen.Variables.Count == 1)
		{
			output.Append(", void _");
		}

		output.Append(") TContext = ?;");
	}

	protected void generateVarsAssign(FrameGenVisitor frameGen, String output)
	{
		for (let variable in frameGen.Variables)
		{
			if (variable.value is VarTypeSpec || variable.value is LetTypeSpec)
			{
				Runtime.FatalError("Implicit variable type 'var'/'let' not supported for locals.");
			}
			output.AppendF($"\tvar {variable.key} = ref context.m_{variable.key};\n");
		}
	}

	protected void generateSwitchCases(FrameGenVisitor frameGen, String output)
	{
		CodeGenVisitor codeGen = scope .(null);

		for (let (id, frame) in frameGen.Frames)
		{
			output.AppendF($"case {id}: // {frame.Description ?? frame.Kind.ToString(.. scope .())}\n");

			String caseOutput = codeGen.Output = scope String();

			let cmpStmt = scope CompoundStmt();
			cmpStmt.Statements.AddRange(frame.Statements);
			codeGen.Visit(cmpStmt);
			cmpStmt.Statements.Clear();

			output.Append(caseOutput);

			switch (frame.Exit)
			{
			case .Continue:
				if (frame.Next != null) {
					output.AppendF($"state = {frame.Next.Id};\n");
				} else {
					output.Append("state = -1;\n");
					output.Append("return .Err;\n");
				}
			case .Suspend:
				output.AppendF($"state = {frame.Next.Id};\n");

				if (frame.ResultExpr != null)
				{
					let exprOutput = codeGen.Output = scope String();
					codeGen.Visit(frame.ResultExpr);

					output.AppendF($"return .Ok({exprOutput});\n");
				}
				else
				{
					output.Append("return .Ok;\n");
				}
			case .Jump:
				output.AppendF($"state = {frame.Next.Id};\n");
			case .Return:
				output.Append("state = -1;\n");

				output.Append("return .Err;\n");
				/*if (frame.exitExpr != null)
				{
					let exprOutput = CodeGen.mOutput = scope String();
					CodeGen.Visit(frame.exitExpr);

					output.AppendF($"return .Ok({exprOutput});\n");
				}
				else
				{
					output.Append("return .Ok;\n");
				}*/
			default:
				Runtime.NotImplemented();
			}
		}

		output.TrimEnd();
		output.Insert(0, "\t\t");
		output.Replace("\n", "\n\t\t");
	}
}