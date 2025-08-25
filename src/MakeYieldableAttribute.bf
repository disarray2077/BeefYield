using System;
using System.Reflection;
using System.Diagnostics;
using System.IO;
using BeefParser;
using BeefParser.AST;
using System.Collections;

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

	protected static void mergeLinearFallthroughs(Dictionary<int, Frame> frames)
	{
	    let inlinePredCount = scope Dictionary<int, int>();
	    let predCount = scope Dictionary<int, int>((.)frames.Count);
	    let uniquePred = scope Dictionary<int, Frame>((.)frames.Count);

		// Since inline preds never change during merging (we only move statements),
		// we compute them once to use as a "targeted" set. We then build the
		// Next predecessor counts and track the unique predecessor, if any.
	    for (let kv in frames)
	    {
	        let f = kv.value;

	        for (let t in f.InlinedTargets)
	        {
	            Runtime.Assert(frames.ContainsKey(t.Id));
	            int cnt;
	            if (!inlinePredCount.TryGetValue(t.Id, out cnt))
	                inlinePredCount.Add(t.Id, cnt = 0);
	            inlinePredCount[t.Id] = cnt + 1;
	        }

			if (f.Next != null)
			{
			    let nid = f.Next.Id;

			    int c;
			    if (!predCount.TryGetValue(nid, out c))
			        predCount[nid] = 1;
			    else
			        predCount[nid] = c + 1;

			    Frame prev;
			    if (!uniquePred.TryGetValue(nid, out prev))
			        uniquePred[nid] = f;
			    else
			        uniquePred[nid] = null;
			}
	    }

	    // A header is a node that cannot be merged into its predecessor.
	    // We only need to start compression from such headers.
	    let headers = scope List<Frame>(frames.Count);
	    for (let kv in frames)
	    {
	        let f = kv.value;

	        int cnt;
	        if (!predCount.TryGetValue(f.Id, out cnt))
	            cnt = 0;

	        bool targeted = inlinePredCount.ContainsKey(f.Id);

	        if (targeted || cnt != 1)
	        {
	            headers.Add(f);
	            continue;
	        }

	        let p = uniquePred[f.Id];
	        if (p == null || p.Exit != .Continue)
	            headers.Add(f);
	    }

	    // Greedily absorb successors for each header
	    for (let h in headers)
	    {
			Runtime.Assert(frames.ContainsKey(h.Id));
	        var cur = h;

	        // Only 'Continue' blocks can be extended
	        while (cur.Exit == .Continue && cur.Next != null)
	        {
	            let f = cur.Next;

	            if (f.Exit != .Continue)
	                break;

	            if (inlinePredCount.ContainsKey(f.Id))
	                break;

	            int cntF;
	            if (!predCount.TryGetValue(f.Id, out cntF) || cntF != 1)
	                break;

	            let up = uniquePred[f.Id];
	            if (up != cur) // stale or not uniquely pred'ed by cur
	                break;

	            // Splice f into cur
	            if (!f.Statements.IsEmpty)
	                cur.Statements.AddRange(f.Statements);

	            if (!f.InlinedTargets.IsEmpty)
	                cur.InlinedTargets.AddRange(f.InlinedTargets);

	            cur.[Friend]mNext = f.Next;
	            Debug.Assert(cur.Exit != .Suspend || cur.Next != null);

	            // Maintain uniquePred for f.Next: if it used to be f, it becomes cur
	            if (f.Next != null)
	            {
	                let nxt = f.Next;
	                Frame prevUP;
	                if (uniquePred.TryGetValue(nxt.Id, out prevUP) && prevUP == f)
	                    uniquePred[nxt.Id] = cur;
	            }

	            // Remove f from active set
	            frames.Remove(f.Id);
	            predCount.Remove(f.Id);
	            uniquePred.Remove(f.Id);
	        }
	    }
	}

	protected void generateSwitchCases(FrameGenVisitor frameGen, String output)
	{
		CodeGenVisitor codeGen = scope .(null);
		codeGen.[Friend]mIdentation += 1;

		mergeLinearFallthroughs(frameGen.Frames);

		for (let (id, frame) in frameGen.Frames)
		{
			output.AppendF($"case {id}: // {frame.Description}\n");

			if (!frame.Statements.IsEmpty)
			{
				String caseOutput = codeGen.Output = scope String();

				let cmpStmt = scope CompoundStmt();
				cmpStmt.Statements.AddRange(frame.Statements);
				codeGen.Visit(cmpStmt);
				cmpStmt.Statements.Clear();

				output.Append(caseOutput);
			}

			switch (frame.Exit)
			{
			case .Continue:
				if (frame.Next != null)
				{
					output.AppendF($"\tstate = {frame.Next.Id}; // {frame.Next.Description}\n");
                    output.Append("\tcontinue;\n");
				}
				else
				{
					output.Append("\tstate = -1;\n");
					output.Append("\treturn .Err;\n");
				}
			case .Suspend:
				output.AppendF($"\tstate = {frame.Next.Id}; // {frame.Next.Description};\n");

				if (frame.ResultExpr != null)
				{
					let exprOutput = codeGen.Output = scope String();
					codeGen.Visit(frame.ResultExpr);

					output.AppendF($"\treturn .Ok({exprOutput});\n");
				}
				else
				{
					output.Append("\treturn .Ok;\n");
				}
			case .Jump:
				output.AppendF($"\tstate = {frame.Next.Id}; // {frame.Next.Description};\n");
                output.Append("\tcontinue;\n");
			case .Return:
				output.Append("\tstate = -1;\n");
				output.Append("\treturn .Err;\n");
			default:
				Runtime.NotImplemented();
			}
		}

		output.TrimEnd();
		output.Insert(0, "\t\t");
		output.Replace("\n", "\n\t\t");
	}
}