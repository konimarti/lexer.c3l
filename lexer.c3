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
        CT_CONST_IDENT, CT_TYPE_IDENT, CT_IDENT,

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

fn char Lexer.peek(&self)
{
	if (self.at_end()) return 0;
	return self.input[self.pos];
}

fn char Lexer.peek2(&self)
{
	if (self.pos + 1 >= self.input.len) return 0;
	return self.input[self.pos + 1];
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
		case '\n': self.advance()!; return self.emit_token(EOL);
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
	TokenType type = INTEGER;
	while (!self.at_end() && (c = self.peek()) && (is_digit(c) || c == '-' ||
		(i > 0 && (ascii::is_xdigit(c) || ascii::is_bdigit(c) || ascii::is_odigit(c) ||
		        c == '.' || c == 'e' || c == 'E' || c == '+' ||
			c == 'b' || c == 'B' || c == 'x' || c == 'X' ||
			c == 'o' || c == 'O' || c == 'p' || c == 'P' ||
			c == 'u' || c == 'U' || c == 'l' || c == 'L' ||
			c == 'i' || c == 'f' || c == 'd' || c == '_'))))
	{
		if ((c == '+' || c == '-') && (prev != 'e' && prev != 'E' && prev != 'p' && prev != 'P')) break;
		if (c == '.' && self.peek2() == '.') break;
		if (c == '.' || c == 'p' || c == 'P') type = REAL;
		self.advance()!;
		i++;
		prev = c;
	}

	// Handle real-type suffixes (f, d) and e, E
	if (type == INTEGER)
	{
		usz len = self.pos - self.token_start;
		String str = self.input[self.token_start:len];
		bool hex_prefix = str.starts_with("0x") || str.starts_with("0X");
		bool realtype = str.ends_with("f") || str.ends_with("d") || str.contains("e") || str.contains("E");
		if (!hex_prefix && realtype) type = REAL;
	}

	return self.emit_token(type);
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
	return self.emit_token(classify(str, str[0]));
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
			return self.emit_token(classify(str));
	}
}

fn void test_classify_str() @test
{
	assert(classify("AABB") == CONST_IDENT);
	assert(classify("Aabb") == TYPE_IDENT);
	assert(classify("aabb") == IDENT);
	assert(classify("aaBb") == IDENT);
	assert(classify("@AABB", '@') == AT_CONST_IDENT);
	assert(classify("@Aabb", '@') == AT_TYPE_IDENT);
	assert(classify("@aabb", '@') == AT_IDENT);
	assert(classify("#AABB", '#') == HASH_CONST_IDENT);
	assert(classify("#Aabb", '#') == HASH_TYPE_IDENT);
	assert(classify("#aabb", '#') == HASH_IDENT);
	assert(classify("$AABB", '$') == CT_CONST_IDENT);
	assert(classify("$Aabb", '$') == CT_TYPE_IDENT);
	assert(classify("$aabb", '$') == CT_IDENT);
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
			return self.emit_token(classify(str, str[0]));
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
	return self.emit_token(classify(str, str[0]));
}

fn TokenType classify(String s, char prefix = 0)
{
	bool type_ident, const_ident, ident;
	usz caps, nocaps, n;
	n = s.len;
	foreach (c : s)
	{
		switch
		{
			case c >= 'a' && c <= 'z': nocaps++;
			case c >= 'A' && c <= 'Z': if (!nocaps) caps++;
			case c == '_' || c == '$' || c == '#': n--;
		}
	}
	type_ident  = n && caps && nocaps;
	const_ident = n && caps && nocaps == 0;
	ident       = n && caps == 0 && nocaps;
	switch (prefix)
	{
		case '@':
			if (type_ident)  return AT_TYPE_IDENT;
			if (const_ident) return AT_CONST_IDENT;
			if (ident)       return AT_IDENT;
		case '#':
			if (type_ident)  return HASH_TYPE_IDENT;
			if (const_ident) return HASH_CONST_IDENT;
			if (ident)       return HASH_IDENT;
		case '$':
			if (type_ident)  return CT_TYPE_IDENT;
			if (const_ident) return CT_CONST_IDENT;
			if (ident)       return CT_IDENT;
		default:
			if (type_ident)  return TYPE_IDENT;
			if (const_ident) return CONST_IDENT;
			if (ident)       return IDENT;
			return IDENT;
	}
	return INVALID;
}

struct DocLexer
{
	Splitter splitter;
	Lexer    lexer;
	bool     lexer_init;
}

fn DocLexer* DocLexer.init(&self, String doc_str)
{
	*self = {
		.splitter   = doc_str.strip("<*").strip_end("*>").tokenize_all("\n", true),
		.lexer      = {},
		.lexer_init = false,
	};
	return self;
}

fn Token? DocLexer.next(&self)
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
	DocLexer dl;
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

module c3::number;

enum NumberState : const inline char
{
	INIT    = 0,
	INTEGER = 1,
	ZERO    = 2,
	HEXINT  = 3,
	OCTINT  = 4,
	BININT  = 5,
	REAL    = 6,
	ERROR   = 7,
	HEXREAL = 8
}

bool[NumberState.len] accept_number_states = { [NumberState.INTEGER] = true, [NumberState.REAL] = true };

NumberState[][] transitions = {
	// Alphabet
	// [0]      [1]      [2-7]    [8-9]    [_]      [aA]     [bB]     [cC]     [dD]    [eE]      [fF]     [iI]     [lL]     [oO]    [pP]     [uU]     [xX]    [+-]     [.]      [eof]
	{  ZERO,    INTEGER, INTEGER, INTEGER, ERROR,   ERROR,   ERROR,   ERROR,   ERROR,  ERROR,    ERROR,   ERROR,   ERROR,   ERROR,  ERROR,   ERROR,   ERROR,  INIT,    ERROR,   ERROR   }, // State 0: INIT
	{  INTEGER, INTEGER, INTEGER, INTEGER, INTEGER, ERROR,   ERROR,   ERROR,   REAL,   REAL,     REAL,    INTEGER, INTEGER, ERROR,  REAL,    INTEGER, ERROR,  ERROR,   REAL,    INTEGER }, // State 1: INTEGER
	{  INTEGER, INTEGER, INTEGER, INTEGER, INTEGER, ERROR,   BININT,  ERROR,   ERROR,  ERROR,    ERROR,   ERROR,   ERROR,   OCTINT, ERROR,   ERROR,   HEXINT, ERROR,   ERROR,   ERROR   }, // State 2: ZERO
	{  HEXINT,  HEXINT,  HEXINT,  HEXINT,  HEXINT,  HEXINT,  HEXINT,  HEXINT,  HEXINT, HEXINT,   HEXINT,  INTEGER, INTEGER, ERROR,  HEXREAL, INTEGER, ERROR,  ERROR,   HEXREAL, INTEGER }, // State 3: HEXINT
	{  OCTINT,  OCTINT,  OCTINT,  ERROR,   OCTINT,  ERROR,   ERROR,   ERROR,   ERROR,  ERROR,    ERROR,   INTEGER, INTEGER, ERROR,  ERROR,   INTEGER, ERROR,  ERROR,   ERROR,   INTEGER }, // State 4: OCTINT
	{  BININT,  BININT,  ERROR,   ERROR,   BININT,  ERROR,   ERROR,   ERROR,   ERROR,  ERROR,    ERROR,   INTEGER, INTEGER, ERROR,  ERROR,   INTEGER, ERROR,  ERROR,   ERROR,   INTEGER }, // State 5: BININT
	{  REAL,    REAL,    REAL,    REAL,    REAL,    ERROR,   ERROR,   ERROR,   REAL,   REAL,     REAL,    ERROR,   ERROR,   ERROR,  REAL,    ERROR,   ERROR,  REAL,    ERROR,   REAL    }, // State 6: REAL
	{  ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,   ERROR,  ERROR,    ERROR,   ERROR,   ERROR,   ERROR,  ERROR,   ERROR,   ERROR,  ERROR,   ERROR,   ERROR   }, // State 7: ERROR
	{  HEXREAL, HEXREAL, HEXREAL, HEXREAL, HEXREAL, HEXREAL, HEXREAL, HEXREAL, HEXREAL, HEXREAL, HEXREAL, ERROR,   ERROR,   ERROR,  HEXREAL, ERROR,   ERROR,  HEXREAL, ERROR,   REAL    }, // State 8: HEXREAL
};


fn NumberState next_state(NumberState s, char c, bool eol = false)
{
	switch
	{
		case c == '0':             return transitions[s][0];
		case c == '1':             return transitions[s][1];
		case c >= '2' && c <= '7': return transitions[s][2];
		case c >= '8' && c <= '9': return transitions[s][3];
		case c == '_':             return transitions[s][4];
		case c == 'a' || c == 'A': return transitions[s][5];
		case c == 'b' || c == 'B': return transitions[s][6];
		case c == 'c' || c == 'C': return transitions[s][7];
		case c == 'd' || c == 'D': return transitions[s][8];
		case c == 'e' || c == 'E': return transitions[s][9];
		case c == 'f' || c == 'F': return transitions[s][10];
		case c == 'i' || c == 'I': return transitions[s][11];
		case c == 'l' || c == 'L': return transitions[s][12];
		case c == 'o' || c == 'O': return transitions[s][13];
		case c == 'p' || c == 'P': return transitions[s][14];
		case c == 'u' || c == 'U': return transitions[s][15];
		case c == 'x' || c == 'X': return transitions[s][16];
		case c == '+' || c == '-': return transitions[s][17];
		case c == '.':             return transitions[s][18];
		case eol:                  return transitions[s][19];
		default:                   return ERROR;
	}
}


struct TestCase
{
	String      str;
	NumberState want;
}

fn void test_number_state() @test
{
	TestCase[*] tests = {
		{ .str  = "123",        .want = INTEGER },
		{ .str  = "123ul",      .want = INTEGER },
		{ .str  = "123i32",     .want = INTEGER },
		{ .str  = "0xdeadbeeF", .want = INTEGER },
		{ .str  = "0xcafeUL",   .want = INTEGER },
		{ .str  = "0xbeeF.123", .want = REAL },
		{ .str  = "0b1001.001", .want = ERROR },
		{ .str  = "0b123",      .want = ERROR },
		{ .str  = "0b101UL",    .want = INTEGER },
		{ .str  = "123.0",      .want = REAL },
		{ .str  = "123.0e-10",  .want = REAL },
		{ .str  = "123f",       .want = REAL },
		{ .str  = "123d",       .want = REAL },
	};

	foreach (tc: tests)
	{
		NumberState s = INIT;
		foreach (c: tc.str) s = next_state(s, c);
		s = next_state(s, 0, true);
		assert(s == tc.want, "wrong state: got: %s, want: %s", s, tc.want);
	}
}

