module c3::lexer;

import std::io;
import std::collections::list;
import std::ascii;

faultdef INVALID_CHAR, CONTRACT_END;

enum TokenType : ushort
{
	INVALID,

	// Operators
	BIT_NOT, BANG, PLUS, MINUS, STAR, DIV, MOD,
	QUESTION, OPTELSE, ELVIS, BANGBANG, BUILTIN,

	// Assignment
	EQ, SHR_ASSIGN, SHL_ASSIGN, ADD_ASSIGN, MINUS_ASSIGN,
	MUL_ASSIGN, DIV_ASSIGN, MOD_ASSIGN, AND_ASSIGN, XOR_ASSIGN,
	OR_ASSIGN,

	// Comparison
	AMP, BIT_OR, BIT_XOR, LESS, GREATER, SHR_OP, SHL_OP, INC_OP, DEC_OP,
	AND, OR, LE_EQ, GE_EQ, EQEQ, NOT_EQUAL, CT_AND_OP,
	CT_OR_OP, CT_CONCAT_ASSIGN, CT_CONCAT_OP, CT_TERNARY,

	// Punctuation
	EOS, COLON, SCOPE, COMMA, DOT, DOTDOT, ELLIPSIS,

	// Structure
	LBRACE, RBRACE, LBRACKET, RBRACKET, LPAREN, RPAREN,
	ARROW, IMPLIES, LVEC, RVEC,


	// Comments and Contracts
	CONTRACT, LCOMMENT, BCOMMENT,

	// Identifiers and Strings
	STRING, CHAR_LITERAL, BYTES, INTEGER, REAL, IDENT, TYPE_IDENT, CONST_IDENT,
	AT_IDENT, AT_TYPE_IDENT, AT_CONST_IDENT, HASH_IDENT, HASH_TYPE_IDENT,
	HASH_CONST_IDENT,

	// Keywords
	ALIAS, ASM, ASSERT, ATTRDEF, BITSTRUCT, CONST, ENUM,
	FAULTDEF, FUNC, IMPORT, INTERFACE, MACRO, MODULE, STRUCT,
	UNION, TYPEDEF, BREAK, CASE, CATCH, CONTINUE, DEFAULT,
	DEFER, DO, ELSE, EXTERN, FALSE, FOR, FOREACH, FOREACH_R,
	IF, INLINE, LENGTHOF, NEXTCASE, NUL, RETURN, STATIC, SWITCH,
	TLOCAL, TRUE, TRY, VAR, WHILE,

	// Base Types (base_type_no_generic)
	VOID, BOOL, CHAR, ICHAR, SHORT, USHORT, INT, UINT, LONG,
	ULONG, INT128, UINT128, FLOAT, DOUBLE, FLOAT16, BFLOAT16,
	FLOAT128, IPTR, UPTR, ISZ, USZ, FAULT, ANY, TYPEID,
        CT_IDENT, CT_TYPE_IDENT, CT_CONST_IDENT,

	CT_ALIGNOF, CT_ASSERT, CT_ASSIGNABLE, CT_CASE, CT_DEFAULT,
	CT_DEFINED, CT_ECHO, CT_ELSE, CT_ENDFOR, CT_ENDFOREACH,
	CT_ENDIF, CT_ENDSWITCH, CT_ERROR, CT_EVAL, CT_EVALTYPE,
	CT_EXEC, CT_EXTNAMEOF, CT_FEATURE, CT_FOR, CT_FOREACH,
	CT_IF, CT_IS_CONST, CT_INCLUDE, CT_KINDOF, CT_NAMEOF, CT_OFFSETOF,
	CT_QNAMEOF, CT_SIZEOF, CT_STRINGIFY, CT_SWITCH, CT_TYPEFROM,
	CT_TYPEOF, CT_VAARG, CT_VACONST, CT_VACOUNT, CT_VAEXPR,
	CT_VAREF, CT_VASPLAT, CT_VATYPE,

	EOL, EOF,
}

struct Token (Printable)
{
	TokenType type;
	String    text;
	usz       offset;
	usz       len;
	usz       ln, col;
	usz       nl_before;
}

fn usz? Token.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	n += f.printf("<%s>", self.type)!;
	if (self.text.len)
	{
		@pool() {
			n += f.printf(" %s", self.text.tescape(true))!;
		};
	}
	return n;
}

struct Lexer
{
	String input;
	bool emit_eol;
	usz  pos;
	usz  ln, col;
	usz  token_start;
	usz  nl_before;
}

fn Lexer* Lexer.init(&self, String input, bool emit_eol = false)
{
	*self = { .input = input, .emit_eol = emit_eol, .pos = 0, .token_start = 0,
		.nl_before = 0, .ln = 1, .col = 1 };
	return self;
}

fn void Lexer.report_error(&self, String msg)
{
	io::eprintfn("LEXER ERROR at Ln: %d, Col: %d -- %s", self.ln, self.col, msg);
}

fn bool is_lf(char c) @inline => c == '\n';
fn bool is_ws(char c) @inline => @ok(" \t\r\n".index_of_char(c));
fn bool is_digit(char c) @inline => ascii::is_digit(c);
fn bool is_ident(char c) @inline => ascii::is_alnum(c) || c == '_';

fn char? Lexer.advance(&self)
{
	char c;

	if (self.at_end()) return io::EOF?;

	c = self.input[self.pos];
	self.pos++;

	self.col++;
	if (is_lf(c))
	{
		self.ln++;
		self.nl_before++;
		self.col = 1;
	}
	return c;
}

fn bool Lexer.at_end(&self) => self.pos >= self.input.len;

fn char Lexer.peek(&self, usz ahead = 0)
{
	if (self.pos + ahead >= self.input.len) return 0;
	return self.input[self.pos + ahead];
}

fn bool Lexer.must(&self, String s)
{
	usz n = s.len;
	if (self.pos+n-1 < self.input.len && self.input[self.pos:n] == s)
	{
		while (n--) (void)self.advance();
		return true;
	}
	return false;
}

<*
 Emit token from lexer.
*>
fn Token Lexer.emit_token(&self, TokenType type)
{
	usz len = self.pos - self.token_start;
	Token tok = {
		.type      = type,
		.offset    = self.token_start,
		.len       = len,
		.ln        = self.ln,
		.col       = self.col,
		.text      = self.input[self.token_start:len],
		.nl_before = self.nl_before
	};
	self.nl_before = 0;
	return tok;
}

<*
 Lex the next token.
*>
fn Token? Lexer.next(&self)
{
	char c;
	TokenType type;

	self.scan_whitespace()!;

	self.token_start = self.pos;
	if (self.at_end()) return self.emit_token(EOF);

	switch (c = self.peek())
	{
		case ';': self.advance()!; return self.emit_token(EOS);
		case ',': self.advance()!; return self.emit_token(COMMA);
		case '~': self.advance()!; return self.emit_token(BIT_NOT);
		case '^':
			switch
			{
				case self.must("^="): type = XOR_ASSIGN;
				case self.must("^"):  type = BIT_XOR;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case '*':
			switch
			{
				case self.must("*="): type = MUL_ASSIGN;
				case self.must("*"):  type = STAR;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case '%':
			switch
			{
				case self.must("%="): type = MOD_ASSIGN;
				case self.must("%"):  type = MOD;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case '.':
			switch
			{
				case self.must("..."): type = ELLIPSIS;
				case self.must(".."):  type = DOTDOT;
				case self.must("."):   type = DOT;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case '+':
			switch
			{
				case self.must("+++="): type = CT_CONCAT_ASSIGN;
				case self.must("+++"):  type = CT_CONCAT_OP;
				case self.must("++"):   type = INC_OP;
				case self.must("+="):   type = ADD_ASSIGN;
				case self.must("+"):    type = PLUS;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case '-':
			switch
			{
				case self.must("--"): type = DEC_OP;
				case self.must("-="): type = MINUS_ASSIGN;
				case self.must("->"): type = ARROW;
				case self.must("-"):  type = MINUS;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case ':':
			switch
			{
				case self.must("::"):  type = SCOPE;
				case self.must(":"):   type = COLON;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case '!':
			switch
			{
				case self.must("!!"):  type = BANGBANG;
				case self.must("!="):  type = NOT_EQUAL;
				case self.must("!"):   type = BANG;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case '?':
			switch
			{
				case self.must("???"): type = CT_TERNARY;
				case self.must("??"):  type = OPTELSE;
				case self.must("?:"):  type = ELVIS;
				case self.must("?"):   type = QUESTION;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case '|':
			switch
			{
				case self.must("|||"): type = CT_OR_OP;
				case self.must("||"):  type = OR;
				case self.must("|="):  type = OR_ASSIGN;
				case self.must("|"):   type = BIT_OR;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case '&':
			switch
			{
				case self.must("&&&"): type = CT_AND_OP;
				case self.must("&&"):  type = AND;
				case self.must("&="):  type = AND_ASSIGN;
				case self.must("&"):   type = AMP;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case '=':
			switch
			{
				case self.must("=>"):  type = IMPLIES;
				case self.must("=="):  type = EQEQ;
				case self.must("="):   type = EQ;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);
		case '>':
			switch
			{
				case self.must(">>="): type = SHR_ASSIGN;
				case self.must(">>"):  type = SHR_OP;
				case self.must(">="):  type = GE_EQ;
				case self.must(">]"):  type = RVEC;
				case self.must(">"):   type = GREATER;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);

		case '[':
			switch
			{
				case self.must("[<"):  type = LVEC;
				case self.must("["):   type = LBRACKET;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);

		case ']': self.advance()!; return self.emit_token(RBRACKET);
		case '{': self.advance()!; return self.emit_token(LBRACE);
		case '}': self.advance()!; return self.emit_token(RBRACE);
		case '(': self.advance()!; return self.emit_token(LPAREN);
		case ')': self.advance()!; return self.emit_token(RPAREN);

		case '/':
			switch
			{
				case self.must("//"): self.scan_line_comment()!;  type = LCOMMENT;
				case self.must("/*"): self.scan_block_comment()!; type = BCOMMENT;
				case self.must("/="): type = DIV_ASSIGN;
				case self.must("/") : type = DIV;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);

		case '<':
			switch
			{
				case self.must("<*"):  self.scan_contract()!; type = CONTRACT;
				case self.must("<<="): type = SHL_ASSIGN;
				case self.must("<<"):  type = SHL_OP;
				case self.must("<="):  type = LE_EQ;
				case self.must("<") :  type = LESS;
				default: return INVALID_CHAR?;
			}
			return self.emit_token(type);

		case '$': return self.lex_compile_time()!;
		case '@': return self.lex_attribute();
		case '#':
			switch
			{
				case self.must("#!"):
					self.scan_line_comment()!;
					return self.emit_token(LCOMMENT);
				default:
					return self.lex_hash_ident()!;
			}

		case 'b':
		case 'x':
			switch
			{
				case self.must("b64\""): self.scan_until('"')!;
				case self.must("b64'"):  self.scan_until('\'')!;
				case self.must("b64`"):  self.scan_until('`')!;
				case self.must("x\""):   self.scan_until('"')!;
				case self.must("x'"):    self.scan_until('\'')!;
				case self.must("x`"):    self.scan_until('`')!;
				default: return self.lex_ident()!;
			}
			return self.emit_token(BYTES);

		case '\'':
			self.scan_string()!;
			return self.emit_token(CHAR_LITERAL);
		case '"':
		case '`':
			self.scan_string()!;
			return self.emit_token(STRING);

		case '\n':
			self.advance()!;
			return self.emit_token(EOL);

		default:
			if (is_digit(c)) return self.lex_number()!;
			if (is_ident(c)) return self.lex_ident()!;
			@pool() {
			self.report_error(string::tformat(
				"encountered invalid char: ""'%c'", c).tescape());
			};
			return INVALID_CHAR?;
	}
}

fn void? Lexer.scan_whitespace(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && is_ws(c))
	{
		if (self.emit_eol && c == '\n') break;
		self.advance()!;
	}
}

fn void? Lexer.scan_until(&self, char until)
{
	while (!self.at_end())
	{
		if (until == self.advance()!) return;
	}
}

fn void? Lexer.scan_string(&self)
{
	char quote, c;
	quote = self.peek();
	switch (quote)
	{
		case '"' :
		case '\'':
			self.advance()!; // Consume '"' or '\''
			while (!self.at_end() && (c = self.peek()) && c != quote)
			{
				if (c == '\\') self.advance()!; // Consume '\'
				self.advance()!;
			}
			self.advance()!; // Consume '"' or '\''
		case '`' :
			self.advance()!; // Consume '`'
			while(!self.at_end() && (c = self.peek()) && c != quote)
			{
				self.advance()!;
			}
			self.advance()!; // Consume '`'
	}
}

fn void? Lexer.scan_line_comment(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && (c != '\n' && c != '\r'))
	{
		self.advance()!;
	}
}

fn void? Lexer.scan_block_comment(&self)
{
	usz depth = 1;
	while (!self.at_end() && depth != 0)
	{
		switch
		{
			case self.must("/*"): depth++;
			case self.must("*/"): depth--;
			default: self.advance()!;
		}
	}
}

fn void? Lexer.scan_contract(&self)
{
	while (!self.at_end() && !self.must("*>")) self.advance()!;
}

fn Token? Lexer.lex_number(&self)
{
	char c, prev;
	int i = 0;
	while (!self.at_end() && (c = self.peek()) && (is_digit(c) || c == '-' ||
		(i > 0 && (ascii::is_xdigit(c) || ascii::is_bdigit(c) || ascii::is_odigit(c) ||
		        c == '.' || c == 'e' || c == 'E' || c == '+' ||
			c == 'b' || c == 'B' || c == 'x' || c == 'X' ||
			c == 'o' || c == 'O' || c == 'p' || c == 'P' ||
			c == 'u' || c == 'U' || c == 'l' || c == 'L' ||
			c == 'i' || c == 'f' || c == 'd' || c == '_'))))
	{
		if ((c == '+' || c == '-') && (prev != 'e' && prev != 'E' && prev != 'p' && prev != 'P')) break;
		if (c == '.' && self.peek(1) == '.') break;
		self.advance()!;
		prev = c;
		i++;
	}

	usz len = self.pos - self.token_start;
	String str = self.input[self.token_start:len];
	return self.emit_token(number::classify(str));
}

fn Token? Lexer.lex_attribute(&self)
{
	char c;
	while (!self.at_end() && (c = self.peek()) && (is_ident(c) || c == '@' ))
	{
		self.advance()!;
	}

	usz len = self.pos - self.token_start;
	String str = self.input[self.token_start:len];
	return self.emit_token(ident::classify(str));
}

fn Token? Lexer.lex_ident(&self)
{
	char c;
	while ((c = self.peek()) && (is_ident(c)))
	{
		self.advance()!;
	}

	usz len = self.pos - self.token_start;
	String str = self.input[self.token_start:len];
	switch (str)
	{
		// Top-Level Explicit Keywords
		case "alias":     return self.emit_token(ALIAS);
		case "attrdef":   return self.emit_token(ATTRDEF);
		case "bitstruct": return self.emit_token(BITSTRUCT);
		case "const":     return self.emit_token(CONST);
		case "enum":      return self.emit_token(ENUM);
		case "faultdef":  return self.emit_token(FAULTDEF);
		case "fn":        return self.emit_token(FUNC);
		case "import":    return self.emit_token(IMPORT);
		case "interface": return self.emit_token(INTERFACE);
		case "macro":     return self.emit_token(MACRO);
		case "module":    return self.emit_token(MODULE);
		case "typedef":   return self.emit_token(TYPEDEF);
		case "struct":    return self.emit_token(STRUCT);
		case "union":     return self.emit_token(UNION);

		// Explicit Keywords
		case "any":       return self.emit_token(ANY);
		case "asm":       return self.emit_token(ASM);
		case "assert":    return self.emit_token(ASSERT);
		case "break":     return self.emit_token(BREAK);
		case "case":      return self.emit_token(CASE);
		case "catch":     return self.emit_token(CATCH);
		case "continue":  return self.emit_token(CONTINUE);
		case "default":   return self.emit_token(DEFAULT);
		case "defer":     return self.emit_token(DEFER);
		case "do":        return self.emit_token(DO);
		case "else":      return self.emit_token(ELSE);
		case "false":     return self.emit_token(FALSE);
		case "for":       return self.emit_token(FOR);
		case "foreach":   return self.emit_token(FOREACH);
		case "foreach_r": return self.emit_token(FOREACH_R);
		case "if":        return self.emit_token(IF);
		case "lengthof":  return self.emit_token(LENGTHOF);
		case "nextcase":  return self.emit_token(NEXTCASE);
		case "null":      return self.emit_token(NUL);
		case "return":    return self.emit_token(RETURN);
		case "static":    return self.emit_token(STATIC);
		case "switch":    return self.emit_token(SWITCH);
		case "true":      return self.emit_token(TRUE);
		case "try":       return self.emit_token(TRY);
		case "var":       return self.emit_token(VAR);
		case "while":     return self.emit_token(WHILE);

		case "extern":    return self.emit_token(EXTERN);
		case "inline":    return self.emit_token(INLINE);
		case "tlocal":    return self.emit_token(TLOCAL);

		// Base Types
		case "void":      return self.emit_token(VOID);
		case "bool":      return self.emit_token(BOOL);
		case "char":      return self.emit_token(CHAR);
		case "ichar":     return self.emit_token(ICHAR);
		case "short":     return self.emit_token(SHORT);
		case "ushort":    return self.emit_token(USHORT);
		case "int":       return self.emit_token(INT);
		case "uint":      return self.emit_token(UINT);
		case "long":      return self.emit_token(LONG);
		case "ulong":     return self.emit_token(ULONG);
		case "int128":    return self.emit_token(INT128);
		case "uint128":   return self.emit_token(UINT128);
		case "iptr":      return self.emit_token(IPTR);
		case "uptr":      return self.emit_token(UPTR);
		case "isz":       return self.emit_token(ISZ);
		case "usz":       return self.emit_token(USZ);
		case "float":     return self.emit_token(FLOAT);
		case "double":    return self.emit_token(DOUBLE);
		case "float16":   return self.emit_token(FLOAT16);
		case "bfloat16":  return self.emit_token(BFLOAT16);
		case "float128":  return self.emit_token(FLOAT128);
		case "fault":     return self.emit_token(FAULT);
		case "typeid":    return self.emit_token(TYPEID);

		default:
			return self.emit_token(ident::classify(str));
	}
}

fn Token? Lexer.lex_compile_time(&self)
{
	char c;
	switch
	{
		case self.must("$$"): return self.emit_token(BUILTIN);
		case self.must("$"): break;
	}
	while (!self.at_end() && (c = self.peek()) && is_ident(c))
	{
		self.advance()!;
	}

	usz len = self.pos - self.token_start;
	String str = self.input[self.token_start:len];
	switch (str)
	{
		// Compile time
		case "$alignof":    return self.emit_token(CT_ALIGNOF);
		case "$assert":     return self.emit_token(CT_ASSERT);
		case "$assignable": return self.emit_token(CT_ASSIGNABLE);
		case "$case":       return self.emit_token(CT_CASE);
		case "$default":    return self.emit_token(CT_DEFAULT);
		case "$defined":    return self.emit_token(CT_DEFINED);
		case "$echo":       return self.emit_token(CT_ECHO);
		case "$else":       return self.emit_token(CT_ELSE);
		case "$endfor":     return self.emit_token(CT_ENDFOR);
		case "$endforeach": return self.emit_token(CT_ENDFOREACH);
		case "$endif":      return self.emit_token(CT_ENDIF);
		case "$endswitch":  return self.emit_token(CT_ENDSWITCH);
		case "$error":      return self.emit_token(CT_ERROR);
		case "$eval":       return self.emit_token(CT_EVAL);
		case "$evaltype":   return self.emit_token(CT_EVALTYPE);
		case "$exec":       return self.emit_token(CT_EXEC);
		case "$extnameof":  return self.emit_token(CT_EXTNAMEOF);
		case "$feature":    return self.emit_token(CT_FEATURE);
		case "$for":        return self.emit_token(CT_FOR);
		case "$foreach":    return self.emit_token(CT_FOREACH);
		case "$if":         return self.emit_token(CT_IF);
		case "$is_const":   return self.emit_token(CT_IS_CONST);
		case "$include":    return self.emit_token(CT_INCLUDE);
		case "$kindof":     return self.emit_token(CT_KINDOF);
		case "$nameof":     return self.emit_token(CT_NAMEOF);
		case "$offsetof":   return self.emit_token(CT_OFFSETOF);
		case "$qnameof":    return self.emit_token(CT_QNAMEOF);
		case "$sizeof":     return self.emit_token(CT_SIZEOF);
		case "$stringify":  return self.emit_token(CT_STRINGIFY);
		case "$switch":     return self.emit_token(CT_SWITCH);
		case "$typefrom":   return self.emit_token(CT_TYPEFROM);
		case "$typeof":     return self.emit_token(CT_TYPEOF);
		case "$vaarg":      return self.emit_token(CT_VAARG);
		case "$vaconst":    return self.emit_token(CT_VACONST);
		case "$vacount":    return self.emit_token(CT_VACOUNT);
		case "$vaexpr":     return self.emit_token(CT_VAEXPR);
		case "$varef":      return self.emit_token(CT_VAREF);
		case "$vasplat":    return self.emit_token(CT_VASPLAT);
		case "$vatype":     return self.emit_token(CT_VATYPE);

		default:
			return self.emit_token(ident::classify(str));
	}
}

fn Token? Lexer.lex_hash_ident(&self)
{
	char c;
	self.must("#");
	while (!self.at_end() && (c = self.peek()) && is_ident(c))
	{
		self.advance()!;
	}

	usz len = self.pos - self.token_start;
	String str = self.input[self.token_start:len];
	return self.emit_token(ident::classify(str));
}

struct ContractLexer
{
	Splitter splitter;
	Lexer    lexer;
	bool     lexer_init;
}

fn ContractLexer* ContractLexer.init(&self, String doc_str)
{
	*self = {
		.splitter   = doc_str.strip("<*").strip_end("*>").tokenize_all("\n", true),
		.lexer      = {},
		.lexer_init = false,
	};
	return self;
}

fn Token? ContractLexer.next(&self)
{
	if (!self.lexer_init)
	{
		usz pos;
		pos = self.splitter.current;
		while (try next_line = self.splitter.next())
		{
			if (next_line.trim().starts_with("@"))
			{
				// io::printfn("lexer_init: '%s'", self.splitter.string[pos..]);
				self.lexer.init(self.splitter.string[pos..], emit_eol: true);
				self.lexer_init = true;
				break;
			}
			pos = self.splitter.current;
		}
	}
	return self.lexer.next();
}

fn void test_doc_lexer() @test
{
	ContractLexer dl;
	dl.init(`*
		 Check if a character is in a set.

		 @param c : "the character to check"


		 @param [in] set : "String containing the characters"
		 @pure
		 @return "True if a character is in the set"
		 *>`);

	TokenType[] want = {
		AT_IDENT, IDENT, COLON, STRING, EOL, EOL, EOL,
		AT_IDENT, LBRACKET, IDENT, RBRACKET, IDENT, COLON, STRING, EOL,
		AT_IDENT, EOL,
		AT_IDENT, STRING, EOL,
		EOF,
	};

	while (try tok = dl.next() && want.len)
	{
		// io::printfn("got: %s, want: %s", tok.type, want[0]);
		assert(tok.type == want[0], "Token type mismatch: got=%s, but want=%s", tok.type, want[0]);
		want = want[1..];
	}
}

module c3::lexer::number;

enum NumberState : const inline char @private
{
	INIT    = 0,
	INTEGER = 1,
	ZERO    = 2,
	HEXINT  = 3,
	OCTINT  = 4,
	BININT  = 5,
	REAL    = 6,
	ERROR   = 7,
	HEXDEC  = 8,  // Hex decimal: HEXINT "." HEXINT
	INTDEC  = 9,  // Integer decimal: INT "." INT
	SCINOT  = 10, // Scientific notation: 1[eEpP]+10
	EXP     = 11, // Exponent
	EXPSIGN = 12, // Exponent sign: +, -
	INTSUF  = 13, // Int suffixes: [iuUlL]
	REALSUF = 14, // Real suffixes: d, f
}

const NumberState[*][*] TRANSITIONS @private = {
	// Alphabet
	// [0]      [1]      [2-7]    [8-9]    [_]      [aA]     [bB]     [cC]     [dD]     [eE]      [fF]     [i]      [lL]     [oO]    [pP]     [uU]     [xX]    [+-]     [.]
	{  ZERO,    INTEGER, INTEGER, INTEGER, ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,    ERROR,   ERROR,   ERROR,   ERROR,  ERROR,   ERROR,   ERROR,  INIT,    ERROR  }, // State 0:  INIT
	{  INTEGER, INTEGER, INTEGER, INTEGER, INTEGER, ERROR,   ERROR,   ERROR,   REALSUF, SCINOT,   REALSUF, INTSUF,  INTSUF,  ERROR,  ERROR,   INTSUF,  ERROR,  ERROR,   INTDEC }, // State 1:  INTEGER
	{  INTEGER, INTEGER, INTEGER, INTEGER, INTEGER, ERROR,   BININT,  ERROR,   REALSUF, SCINOT,   REALSUF, INTSUF,  INTSUF,  OCTINT, ERROR,   INTSUF,  HEXINT, ERROR,   INTDEC }, // State 2:  ZERO
	{  HEXINT,  HEXINT,  HEXINT,  HEXINT,  HEXINT,  HEXINT,  HEXINT,  HEXINT,  HEXINT,  HEXINT,   HEXINT,  INTSUF,  INTSUF,  ERROR,  SCINOT,  INTSUF,  ERROR,  ERROR,   HEXDEC }, // State 3:  HEXINT
	{  OCTINT,  OCTINT,  OCTINT,  ERROR,   OCTINT,  ERROR,   ERROR,   ERROR,   ERROR,   ERROR,    ERROR,   INTSUF,  INTSUF,  ERROR,  ERROR,   INTSUF,  ERROR,  ERROR,   ERROR  }, // State 4:  OCTINT
	{  BININT,  BININT,  ERROR,   ERROR,   BININT,  ERROR,   ERROR,   ERROR,   ERROR,   ERROR,    ERROR,   INTSUF,  INTSUF,  ERROR,  ERROR,   INTSUF,  ERROR,  ERROR,   ERROR  }, // State 5:  BININT
	{  ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,    ERROR,   ERROR,   ERROR,   ERROR,  ERROR,   ERROR,   ERROR,  ERROR,   ERROR  }, // State 6:  REAL
	{  ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,    ERROR,   ERROR,   ERROR,   ERROR,  ERROR,   ERROR,   ERROR,  ERROR,   ERROR  }, // State 7:  ERROR
	{  HEXDEC,  HEXDEC,  HEXDEC,  HEXDEC,  HEXDEC,  HEXDEC,  HEXDEC,  HEXDEC,  HEXDEC,  HEXDEC,   HEXDEC,  ERROR,   ERROR,   ERROR,  SCINOT,  ERROR,   ERROR,  ERROR,   ERROR  }, // State 8:  HEXDEC
	{  INTDEC,  INTDEC,  INTDEC,  INTDEC,  INTDEC,  ERROR,   ERROR,   ERROR,   REALSUF, SCINOT,   REALSUF, ERROR,   ERROR,   ERROR,  ERROR,   ERROR,   ERROR,  ERROR,   ERROR  }, // State 9:  INTDEC
	{  EXP,     EXP,     EXP,     EXP,     ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,    ERROR,   ERROR,   ERROR,   ERROR,  ERROR,   ERROR,   ERROR,  EXPSIGN, ERROR  }, // State 10: SCINOT
	{  EXP,     EXP,     EXP,     EXP,     ERROR,   ERROR,   ERROR,   ERROR,   REALSUF, ERROR,    REALSUF, ERROR,   ERROR,   ERROR,  ERROR,   ERROR,   ERROR,  ERROR,   ERROR  }, // State 11: EXP
	{  EXP,     EXP,     EXP,     EXP,     ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,    ERROR,   ERROR,   ERROR,   ERROR,  ERROR,   ERROR,   ERROR,  ERROR,   ERROR  }, // State 12: EXPSIGN
	{  ERROR,   INTSUF,  INTSUF,  INTSUF,  ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,    ERROR,   ERROR,   INTSUF,  ERROR,  ERROR,   ERROR,   ERROR,  ERROR,   ERROR  }, // State 13: INTSUF
	{  ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,    ERROR,   ERROR,   ERROR,   ERROR,  ERROR,   ERROR,   ERROR,  ERROR,   ERROR  }, // State 14: REALSUF
};


fn NumberState next_state(NumberState s, char c) @inline @private
{
	switch
	{
		case c == '0':             return TRANSITIONS[s][0];
		case c == '1':             return TRANSITIONS[s][1];
		case c >= '2' && c <= '7': return TRANSITIONS[s][2];
		case c >= '8' && c <= '9': return TRANSITIONS[s][3];
		case c == '_':             return TRANSITIONS[s][4];
		case c == 'a' || c == 'A': return TRANSITIONS[s][5];
		case c == 'b' || c == 'B': return TRANSITIONS[s][6];
		case c == 'c' || c == 'C': return TRANSITIONS[s][7];
		case c == 'd' || c == 'D': return TRANSITIONS[s][8];
		case c == 'e' || c == 'E': return TRANSITIONS[s][9];
		case c == 'f' || c == 'F': return TRANSITIONS[s][10];
		case c == 'i':             return TRANSITIONS[s][11];
		case c == 'l' || c == 'L': return TRANSITIONS[s][12];
		case c == 'o' || c == 'O': return TRANSITIONS[s][13];
		case c == 'p' || c == 'P': return TRANSITIONS[s][14];
		case c == 'u' || c == 'U': return TRANSITIONS[s][15];
		case c == 'x' || c == 'X': return TRANSITIONS[s][16];
		case c == '+' || c == '-': return TRANSITIONS[s][17];
		case c == '.':             return TRANSITIONS[s][18];
		default:                   return ERROR;
	}
}


fn TokenType classify(String s)
{
	NumberState state = INIT;
	foreach (c: s) state = next_state(state, c);
	switch (state)
	{
		case ZERO:
		case HEXINT:
		case OCTINT:
		case BININT:
		case INTSUF:
		case INTEGER:
			return TokenType.INTEGER;
		case INTDEC:
		case EXP:
		case REALSUF:
		case REAL:
			return TokenType.REAL;
		default:
			return TokenType.INVALID;
	}
}

fn void test_number_classify() @test
{
	assert(classify("+")          ==  INVALID  );
	assert(classify("-")          ==  INVALID  );
	assert(classify("0")          ==  INTEGER  );
	assert(classify("-1")         ==  INTEGER  );
	assert(classify("123")        ==  INTEGER  );
	assert(classify("123ul")      ==  INTEGER  );
	assert(classify("123i32")     ==  INTEGER  );
	assert(classify("0xdeadbeeF") ==  INTEGER  );
	assert(classify("0xcafeUL")   ==  INTEGER  );
	assert(classify("0b101UL")    ==  INTEGER  );
	assert(classify("1xbeef")     ==  INVALID  );
	assert(classify("0b1001.001") ==  INVALID  );
	assert(classify("0b123")      ==  INVALID  );
	assert(classify("0xbeeF.123p1") == REAL   );
	assert(classify("0f")         ==   REAL );
	assert(classify("0.5f")       ==   REAL );
	assert(classify("123.0")      ==   REAL );
	assert(classify("123.0e-10")  ==   REAL );
	assert(classify("123f")       ==   REAL );
	assert(classify("123d")       ==   REAL );
}

module c3::lexer::ident;

enum IdentState : const inline char @private {
	INIT_STATE  = 0,
	IDENT_STATE = 1,
	TYPE_STATE  = 2,
	CONST_STATE = 3,
	ERROR_STATE = 4,
}

bool[5] accepting_states @private = { false, true, true, true, false };

const IdentState[*][*] TRANSITIONS @private = {
	// Alphabet
	// [A-Z]        [a-z]        [0-9]        '_'          [$#@]
	{  CONST_STATE, IDENT_STATE, ERROR_STATE, INIT_STATE,  INIT_STATE  }, // State 0: INIT_STATE
	{  IDENT_STATE, IDENT_STATE, IDENT_STATE, IDENT_STATE, ERROR_STATE }, // State 1: IDENT_STATE
	{  TYPE_STATE,  TYPE_STATE,  TYPE_STATE,  TYPE_STATE,  ERROR_STATE }, // State 2: TYPE_STATE
	{  CONST_STATE, TYPE_STATE,  CONST_STATE, CONST_STATE, ERROR_STATE }, // State 3: CONST_STATE
	{  ERROR_STATE, ERROR_STATE, ERROR_STATE, ERROR_STATE, ERROR_STATE }, // State 4: ERROR_STATE
};

fn IdentState next_state(IdentState state, char c) @inline @private
{
	switch
	{
	case c >= 'A' && c <= 'Z': return TRANSITIONS[state][0];
	case c >= 'a' && c <= 'z': return TRANSITIONS[state][1];
	case c >= '0' && c <= '9': return TRANSITIONS[state][2];
	case c == '_':             return TRANSITIONS[state][3];
	case c == '$' || c == '#' || c == '@':
				   return TRANSITIONS[state][4];
	default:                   return ERROR_STATE;
	}
}

fn TokenType classify(String s)
{
	IdentState state = IdentState.INIT_STATE;
	foreach (c: s) state = next_state(state, c);
	if (accepting_states[state])
	{
		ushort offset = (ushort)state - 1;
		switch (s[0])
		{
		case '$': return offset + TokenType.CT_IDENT;
		case '#': return offset + TokenType.HASH_IDENT;
		case '@': return offset + TokenType.AT_IDENT;
		default:  return offset + TokenType.IDENT;
		}
	}
	return INVALID;
}

fn void test_ident_classify() @test
{
	assert(classify("AABB") == CONST_IDENT);
	assert(classify("Aabb") == TYPE_IDENT);
	assert(classify("aabb") == IDENT);
	assert(classify("aaBb") == IDENT);
	assert(classify("@AABB") == AT_CONST_IDENT);
	assert(classify("@Aabb") == AT_TYPE_IDENT);
	assert(classify("@aabb") == AT_IDENT);
	assert(classify("#AABB") == HASH_CONST_IDENT);
	assert(classify("#Aabb") == HASH_TYPE_IDENT);
	assert(classify("#aabb") == HASH_IDENT);
	assert(classify("$AABB") == CT_CONST_IDENT);
	assert(classify("$Aabb") == CT_TYPE_IDENT);
	assert(classify("$aabb") == CT_IDENT);
}


