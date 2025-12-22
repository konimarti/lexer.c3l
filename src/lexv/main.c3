<*
 Validates the c3::lexer with the lexer in the c3c compiler.
 Expects the output of `c3c -E` on stdin.

 The output from `c3c -E` contains two lines per file. The first line starts
 with '#' and contains the file that is being lexed. The second line are the
 tokens separate by a whitespace character(' ').

 Usage: c3c -E lexer.c3 | lexv
*>
module lexv;

import std::io;
import c3::lexer;

fn void main() => @pool()
{
	usz pass, total;
	while READ_INPUT: (try header = io::treadline(io::stdin()))
	{
		if (!header.starts_with("#"))
		{
			io::eprintf("invalid format: expected '#'");
			break READ_INPUT;
		}
		String[] list = header.tsplit(" ");
		if (list.len < 2)
		{
			io::eprintf("invalid header line: expected '# filename'");
			break READ_INPUT;
		}
		String filename = list[1];

		if (try tokens = io::treadline(io::stdin()))
		{
			total++;
			if(try ok = validate(filename, tokens) && ok)
			{
				pass++;
				io::printfn("[✔] %s", filename);
			}
			else
			{
				io::printfn("[x] %s", filename);
			}
		}
		else
		{
			io::eprintf("missing token line?");
			break READ_INPUT;
		}
	}

	io::printn( "Lexer Report");
	io::printn( "------------");
	io::printfn("Passed: %d", pass);
	io::printfn("Total : %d", total);
	if (total > 0) io::printfn("Ratio : %.1f%%", 100.0 * (double)pass / (double)total);

}

fn bool? validate(String filename, String tokens) => @pool()
{
	char[] content = file::load_temp(filename)!;

	DString buf = dstring::temp("");

	Lexer lexer;
	lexer.init((String)content[..]);
	while (!lexer.at_end())
	{
		Token tok = lexer.next()!;

		// Skip trivia tokens
		usz len;
		switch (tok.type)
		{
			case LCOMMENT:
			case BCOMMENT: continue;
			case CONTRACT:
				DString buf2 = dstring::temp("<* ");

				DocLexer dl;
				dl.init(tok.text);
				while (try doctok = dl.next())
				{
					if (doctok.type == EOF) break;
					buf2.append_string(token_to_string(doctok, true));
					buf2.append_char(' ');
				}

				buf2.append_string("*> ");
				len = buf2.str_view().len;
				buf.append_dstring(buf2);
			default:
				buf.append_string(token_to_string(tok));
				buf.append_char(' ');
				len = token_to_string(tok).len + 1;
		}

		String s = buf.str_view();
		if (s != tokens[:s.len])
		{
			io::eprintf("Token mismatch in Ln %d, Col %d -- got: %s, want: %s\n",
				lexer.ln, lexer.col, s[^len..], tokens[s.len-len:len]);
			return false;
		}
	}

	return true;
}

fn String token_to_string(Token tok, bool doc_mode = false)
{
	switch (tok.type)
	{
	case INVALID: return "INVALID_TOKEN";
	case BIT_NOT: return "~";
	case BANG: return "!";
	case PLUS: return "+";
	case MINUS: return "-";
	case STAR: return "*";
	case DIV: return "/";
	case MOD: return "%";
	case QUESTION: return "?";
	case OPTELSE: return "??";
	case ELVIS: return "?:";
	case BANGBANG: return "!!";
	case BUILTIN: return "$$";
	case EQ: return "=";
	case SHR_ASSIGN: return ">>=";
	case SHL_ASSIGN: return "<<=";
	case ADD_ASSIGN: return "+=";
	case MINUS_ASSIGN: return "-=";
	case MUL_ASSIGN: return "*=";
	case DIV_ASSIGN: return "/=";
	case MOD_ASSIGN: return "%=";
	case AND_ASSIGN: return "&=";
	case XOR_ASSIGN: return "^=";
	case OR_ASSIGN: return "|=";
	case AMP: return "&";
	case BIT_OR: return "|";
	case BIT_XOR: return "^";
	case LESS: return "<";
	case GREATER: return ">";
	case SHR_OP: return ">>";
	case SHL_OP: return "<<";
	case INC_OP: return "++";
	case DEC_OP: return "--";
	case AND: return "&&";
	case OR: return "||";
	case LE_EQ: return "<=";
	case GE_EQ: return ">=";
	case EQEQ: return "==";
	case NOT_EQUAL: return "!=";
	case CT_AND_OP: return "&&&";
	case CT_OR_OP: return "|||";
	case CT_CONCAT_OP: return "+++";
	case CT_TERNARY: return "???";
	case EOS: return ";";
	case COLON: return ":";
	case SCOPE: return "::";
	case COMMA: return ",";
	case DOT: return ".";
	case DOTDOT: return "..";
	case ELLIPSIS: return "...";
	case LBRACE: return "{";
	case RBRACE: return "}";
	case LBRACKET: return "[";
	case RBRACKET: return "]";
	case LPAREN: return "(";
	case RPAREN: return ")";
	case ARROW: return "->";
	case IMPLIES: return "=>";
	case LVEC: return "[<";
	case RVEC: return ">]";
	case CONTRACT: return "<* *>";
	case LCOMMENT: return "";
	case BCOMMENT: return "";
	case STRING: return "STRING";
	case CHAR_LITERAL: return "CHAR_LITERAL";
	case BYTES: return "BYTES";
	case INTEGER: return "INTEGER";
	case REAL: return "FLOAT";
	case IDENT: return "IDENT";
	case TYPE_IDENT: return "TYPE_IDENT";
	case CONST_IDENT: return "CONST_IDENT";
	case AT_IDENT: return "MACRO_IDENT";
	case AT_TYPE_IDENT: return "MACRO_TYPE_IDENT";
	case AT_CONST_IDENT: return "MACRO_CONST_IDENT";
	case HASH_IDENT: return "HASH_IDENT";
	case HASH_TYPE_IDENT: return "HASH_TYPE_IDENT";
	case HASH_CONST_IDENT: return "HASH_CONST_IDENT";
	case ALIAS: return tok.text;
	case ASM: return tok.text;
	case ASSERT: return tok.text;
	case ATTRDEF: return tok.text;
	case BITSTRUCT: return tok.text;
	case CONST: return tok.text;
	case ENUM: return tok.text;
	case FAULTDEF: return tok.text;
	case FUNC: return tok.text;
	case IMPORT: return tok.text;
	case INTERFACE: return tok.text;
	case MACRO: return tok.text;
	case MODULE: return tok.text;
	case STRUCT: return tok.text;
	case UNION: return tok.text;
	case TYPEDEF: return tok.text;
	case BREAK: return tok.text;
	case CASE: return tok.text;
	case CATCH: return tok.text;
	case CONTINUE: return tok.text;
	case DEFAULT: return tok.text;
	case DEFER: return tok.text;
	case DO: return tok.text;
	case ELSE: return tok.text;
	case EXTERN: return tok.text;
	case FALSE: return tok.text;
	case FOR: return tok.text;
	case FOREACH: return tok.text;
	case FOREACH_R: return tok.text;
	case IF: return tok.text;
	case INLINE: return tok.text;
	case NEXTCASE: return tok.text;
	case NUL: return tok.text;
	case RETURN: return doc_mode ? "IDENT" : tok.text;
	case STATIC: return tok.text;
	case SWITCH: return tok.text;
	case TLOCAL: return tok.text;
	case TRUE: return tok.text;
	case TRY: return tok.text;
	case VAR: return tok.text;
	case WHILE: return tok.text;
	case VOID: return tok.text;
	case BOOL: return tok.text;
	case CHAR: return tok.text;
	case ICHAR: return tok.text;
	case SHORT: return tok.text;
	case USHORT: return tok.text;
	case INT: return tok.text;
	case UINT: return tok.text;
	case LONG: return tok.text;
	case ULONG: return tok.text;
	case INT128: return tok.text;
	case UINT128: return tok.text;
	case FLOAT: return tok.text;
	case DOUBLE: return tok.text;
	case FLOAT16: return tok.text;
	case BFLOAT16: return tok.text;
	case FLOAT128: return tok.text;
	case IPTR: return tok.text;
	case UPTR: return tok.text;
	case ISZ: return tok.text;
	case USZ: return tok.text;
	case FAULT: return tok.text;
	case ANY: return tok.text;
	case TYPEID: return tok.text;
	case CT_CONST_IDENT: return tok.text;
	case CT_TYPE_IDENT: return tok.text;
	case CT_IDENT: return "CT_IDENT";
	case CT_ALIGNOF: return tok.text;
	case CT_ASSERT: return tok.text;
	case CT_ASSIGNABLE: return tok.text;
	case CT_CASE: return tok.text;
	case CT_DEFAULT: return tok.text;
	case CT_DEFINED: return tok.text;
	case CT_ECHO: return tok.text;
	case CT_ELSE: return tok.text;
	case CT_ENDFOR: return tok.text;
	case CT_ENDFOREACH: return tok.text;
	case CT_ENDIF: return tok.text;
	case CT_ENDSWITCH: return tok.text;
	case CT_ERROR: return tok.text;
	case CT_EVAL: return tok.text;
	case CT_EVALTYPE: return tok.text;
	case CT_EXEC: return tok.text;
	case CT_EXTNAMEOF: return tok.text;
	case CT_FEATURE: return tok.text;
	case CT_FOR: return tok.text;
	case CT_FOREACH: return tok.text;
	case CT_IF: return tok.text;
	case CT_IS_CONST: return tok.text;
	case CT_INCLUDE: return tok.text;
	case CT_NAMEOF: return tok.text;
	case CT_OFFSETOF: return tok.text;
	case CT_QNAMEOF: return tok.text;
	case CT_SIZEOF: return tok.text;
	case CT_STRINGIFY: return tok.text;
	case CT_SWITCH: return tok.text;
	case CT_TYPEFROM: return tok.text;
	case CT_TYPEOF: return tok.text;
	case CT_VAARG: return tok.text;
	case CT_VACONST: return tok.text;
	case CT_VACOUNT: return tok.text;
	case CT_VAEXPR: return tok.text;
	case CT_VAREF: return tok.text;
	case CT_VASPLAT: return tok.text;
	case CT_VATYPE: return tok.text;
	case EOL: return "<EOL>";
	case EOF: return "EOF";
	}
}
