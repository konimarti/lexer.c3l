module c3::lexer;

import std::io, std::core::ascii;

faultdef INVALID_CHAR;

enum TokenType : ushort
{
	INVALID,

	// Operators
	AMP, BIT_OR, BIT_XOR, BIT_NOT, BANG, PLUS, MINUS, STAR, DIV, MOD,
	QUESTION, QUESTQUEST, ELVIS, BANGBANG, BUILTIN, SHR_OP, SHL_OP,
	PLUSPLUS, MINUSMINUS, CT_CONCAT_OP, CT_TERNARY,

	// Assignment
	EQ, SHR_ASSIGN, SHL_ASSIGN, PLUS_ASSIGN, MINUS_ASSIGN, MULT_ASSIGN,
	DIV_ASSIGN, MOD_ASSIGN, BIT_AND_ASSIGN, BIT_XOR_ASSIGN, BIT_OR_ASSIGN,
	CT_CONCAT_ASSIGN,

	// Comparison
	LESS, GREATER, AND, OR, LESS_EQ, GREATER_EQ, EQEQ, NOT_EQUAL, CT_AND_OP,
	CT_OR_OP,

	// Punctuation
	EOS, COLON, SCOPE, COMMA, DOT, DOTDOT, ELLIPSIS, AT, HASH, UNDERSCORE,

	// Structure
	LBRACE, RBRACE, LBRACKET, RBRACKET, LPAREN, RPAREN, ARROW, IMPLIES,
	LVEC, RVEC,

	// Comments and Contracts
	CONTRACT, LINE_COMMENT, BLOCK_COMMENT,

	// Literals (Identifiers and Strings)
	STRING, CHAR_LITERAL, BYTES, INTEGER, REAL, IDENT, TYPE_IDENT,
	CONST_IDENT, AT_IDENT, AT_TYPE_IDENT, AT_CONST_IDENT, HASH_IDENT,
	CT_IDENT, CT_TYPE_IDENT,
	CT_CONST_IDENT,

	// Base Types (base_type_no_generic)
	VOID, BOOL, CHAR, ICHAR, SHORT, USHORT, INT, UINT, LONG, ULONG, INT128,
	UINT128, FLOAT, DOUBLE, FLOAT16, BFLOAT, FLOAT128, IPTR, UPTR, ISZ,
	USZ, FAULT, ANY, TYPEID, UNTYPEDLIST,

	// Keywords
	ALIAS, ASM, ASSERT, ATTRDEF, ATTRMACRO, BITSTRUCT, CONST, CONSTDEF, CONSTSET, ENUM,
	FAULTDEF, FUNC, IMPORT, INTERFACE, MACRO, MODULE, STRUCT, UNION,
	TYPEDEF, BREAK, CASE, CATCH, CONTINUE, DEFAULT, DEFER, DO, ELSE,
	EXTERN, FALSE, FOR, FOREACH, FOREACH_R, IF, INLINE, LENGTHOF, NEXTCASE,
	NULL, RETURN, STATIC, SWITCH, TLOCAL, TRUE, TRY, VAR, WHILE,

	// Compile time keywords (C3 0.8)
	CT_ASSERT, CT_CASE, CT_DEFAULT, CT_DEFINED, CT_ECHO, CT_ELSE, CT_EMBED,
	CT_ENDFOR, CT_ENDFOREACH, CT_ENDIF, CT_ENDSWITCH, CT_ERROR, CT_EVAL,
	CT_EXEC, CT_EXPAND, CT_FEAT, CT_FEATURE, CT_FOR, CT_FOREACH, CT_IF,
	CT_INCLUDE, CT_REFLECT, CT_STRINGIFY, CT_SWITCH, CT_TYPEFROM, CT_TYPEOF,
	CT_VAARG,

	EOL, EOF,
}

struct Token (Printable)
{
	TokenType type;
	String    text;
	sz       offset;
	sz       len;
	<* Line and byte column where the token starts, both 1-based. *>
	sz       ln, col;
	<* Newlines between the previous token and this one. *>
	sz       nl_before;
	<*
	 A string, char or bytes literal, block comment or contract that is never
	 closed. The token runs to the end of its line (`"…"`, `'…'`) or the input.
	*>
	bool     unterminated;
}

fn sz? Token.to_format(&self, Formatter *f) @dynamic
{
	sz n;
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
	sz  pos;
	sz  ln, col;
	sz  token_start;
	sz  token_ln, token_col;
	sz  token_nl;
	sz  nl_before;
	bool unterminated;
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

<*
 Byte classes, looked up in one table: faster than the generic `ascii::` helpers.
*>
const char CLASS_WS    = 1;
const char CLASS_DIGIT = 2;
const char CLASS_IDENT = 4; // [A-Za-z0-9_]
const char CLASS_LOWER = 8;
const char CLASS_UPPER = 16;
const char CLASS_NUMBER = 32; // after the first byte of a number: hex digits and "+.pPxXoOuUlLi_"

const char[256] CHAR_CLASS = {
	[' '] = CLASS_WS, ['\t'] = CLASS_WS, ['\r'] = CLASS_WS, ['\n'] = CLASS_WS,
	['0'..'9'] = CLASS_DIGIT | CLASS_IDENT | CLASS_NUMBER,
	['_'] = CLASS_IDENT | CLASS_NUMBER, ['+'] = CLASS_NUMBER, ['.'] = CLASS_NUMBER,
	['a'..'f'] = CLASS_IDENT | CLASS_LOWER | CLASS_NUMBER,
	['g'..'h'] = CLASS_IDENT | CLASS_LOWER,
	['i'] = CLASS_IDENT | CLASS_LOWER | CLASS_NUMBER,
	['j'..'k'] = CLASS_IDENT | CLASS_LOWER,
	['l'] = CLASS_IDENT | CLASS_LOWER | CLASS_NUMBER,
	['m'..'n'] = CLASS_IDENT | CLASS_LOWER,
	['o'..'p'] = CLASS_IDENT | CLASS_LOWER | CLASS_NUMBER,
	['q'..'t'] = CLASS_IDENT | CLASS_LOWER,
	['u'] = CLASS_IDENT | CLASS_LOWER | CLASS_NUMBER,
	['v'..'w'] = CLASS_IDENT | CLASS_LOWER,
	['x'] = CLASS_IDENT | CLASS_LOWER | CLASS_NUMBER,
	['y'..'z'] = CLASS_IDENT | CLASS_LOWER,
	['A'..'F'] = CLASS_IDENT | CLASS_UPPER | CLASS_NUMBER,
	['G'..'K'] = CLASS_IDENT | CLASS_UPPER,
	['L'] = CLASS_IDENT | CLASS_UPPER | CLASS_NUMBER,
	['M'..'N'] = CLASS_IDENT | CLASS_UPPER,
	['O'..'P'] = CLASS_IDENT | CLASS_UPPER | CLASS_NUMBER,
	['Q'..'T'] = CLASS_IDENT | CLASS_UPPER,
	['U'] = CLASS_IDENT | CLASS_UPPER | CLASS_NUMBER,
	['V'..'W'] = CLASS_IDENT | CLASS_UPPER,
	['X'] = CLASS_IDENT | CLASS_UPPER | CLASS_NUMBER,
	['Y'..'Z'] = CLASS_IDENT | CLASS_UPPER,
};



fn bool is_lf(char c) @inline => c == '\n';
fn bool is_ws(char c) @inline => (CHAR_CLASS[c] & CLASS_WS) != 0;
fn bool is_digit(char c) @inline => (CHAR_CLASS[c] & CLASS_DIGIT) != 0;
fn bool is_ident(char c) @inline => (CHAR_CLASS[c] & CLASS_IDENT) != 0;

<*
 Line and column bookkeeping for one consumed byte (the part of `advance` that
 doesn't move `pos`), for scanners that walk the input with a local index.
*>
fn void Lexer.track_byte(&self, char c) @inline
{
	if (c == '\n')
	{
		self.ln++;
		self.nl_before++;
		self.col = 1;
	}
	else
	{
		self.col++;
	}
}

fn char? Lexer.advance(&self)
{
	char c;

	if (self.at_end()) return io::EOF~;

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

<*
 Skip [A-Za-z0-9_]. These never include a newline, so the line is untouched and
 the column moves once, by the whole run.
*>
fn void Lexer.skip_ident_chars(&self) @inline
{
	String input = self.input;
	sz p = self.pos;
	while (p < input.len && is_ident(input[p])) p++;
	self.col += p - self.pos;
	self.pos = p;
}

fn bool Lexer.at_end(&self) => self.pos >= self.input.len;

fn char Lexer.peek(&self, sz ahead = 0)
{
	if (self.pos + ahead >= self.input.len) return 0;
	return self.input[self.pos + ahead];
}

<*
 Consume `s` if the input continues with it. Patterns are 1-4 bytes, so a byte
 loop beats a call to memcmp. Patterns never contain a newline, so only the
 column moves.
*>
fn bool Lexer.must(&self, String s)
{
	sz n = s.len;
	if (self.pos + n > self.input.len) return false;
	char* in = self.input.ptr + self.pos;
	for (sz i = 0; i < n; i++)
	{
		if (in[i] != s[i]) return false;
	}
	self.pos += n;
	self.col += n;
	return true;
}

fn String Lexer.lexeme(&self)
{
	sz len = self.pos - self.token_start;
	return self.input[self.token_start:len];
}

<*
 Emit token from lexer.
*>
fn Token Lexer.emit_token(&self, TokenType type) @inline
{
	String lexeme = self.lexeme();
	Token tok = {
		.type         = type,
		.offset       = self.token_start,
		.len          = lexeme.len,
		.ln           = self.token_ln,
		.col          = self.token_col,
		.text         = lexeme,
		.nl_before    = self.token_nl,
		.unterminated = self.unterminated,
	};
	self.unterminated = false;
	return tok;
}

<*
 Lex the next token.
*>
fn Token? Lexer.next(&self)
{
	// Newlines inside the previous token belong to it, not to the gap before this one.
	self.nl_before = 0;
	self.scan_whitespace()!;

	self.token_start = self.pos;
	self.token_ln = self.ln;
	self.token_col = self.col;
	self.token_nl = self.nl_before;
	self.unterminated = false;
	if (self.at_end()) return io::EOF~;

	return self.emit_token(self.scan_token()!);
}

<*
 Scan one token, starting at a non-whitespace byte, and return its type.
*>
fn TokenType? Lexer.scan_token(&self)
{
	char c;
	TokenType type;

	switch (c = self.peek())
	{
		case ';': self.advance()!; return EOS;
		case ',': self.advance()!; return COMMA;
		case '~': self.advance()!; return BIT_NOT;
		case '^':
			switch
			{
				case self.must("^="): type = BIT_XOR_ASSIGN;
				case self.must("^"):  type = BIT_XOR;
				default: return INVALID_CHAR~;
			}
			return type;
		case '*':
			switch
			{
				case self.must("*="): type = MULT_ASSIGN;
				case self.must("*"):  type = STAR;
				default: return INVALID_CHAR~;
			}
			return type;
		case '%':
			switch
			{
				case self.must("%="): type = MOD_ASSIGN;
				case self.must("%"):  type = MOD;
				default: return INVALID_CHAR~;
			}
			return type;
		case '.':
			switch
			{
				case self.must("..."): type = ELLIPSIS;
				case self.must(".."):  type = DOTDOT;
				case self.must("."):   type = DOT;
				default: return INVALID_CHAR~;
			}
			return type;
		case '+':
			switch
			{
				case self.must("+++="): type = CT_CONCAT_ASSIGN;
				case self.must("+++"):  type = CT_CONCAT_OP;
				case self.must("++"):   type = PLUSPLUS;
				case self.must("+="):   type = PLUS_ASSIGN;
				case self.must("+"):    type = PLUS;
				default: return INVALID_CHAR~;
			}
			return type;
		case '-':
			switch
			{
				case self.must("--"): type = MINUSMINUS;
				case self.must("-="): type = MINUS_ASSIGN;
				case self.must("->"): type = ARROW;
				case self.must("-"):  type = MINUS;
				default: return INVALID_CHAR~;
			}
			return type;
		case ':':
			switch
			{
				case self.must("::"):  type = SCOPE;
				case self.must(":"):   type = COLON;
				default: return INVALID_CHAR~;
			}
			return type;
		case '!':
			switch
			{
				case self.must("!!"):  type = BANGBANG;
				case self.must("!="):  type = NOT_EQUAL;
				case self.must("!"):   type = BANG;
				default: return INVALID_CHAR~;
			}
			return type;
		case '?':
			switch
			{
				case self.must("???"): type = CT_TERNARY;
				case self.must("??"):  type = QUESTQUEST;
				case self.must("?:"):  type = ELVIS;
				case self.must("?"):   type = QUESTION;
				default: return INVALID_CHAR~;
			}
			return type;
		case '|':
			switch
			{
				case self.must("|||"): type = CT_OR_OP;
				case self.must("||"):  type = OR;
				case self.must("|="):  type = BIT_OR_ASSIGN;
				case self.must("|"):   type = BIT_OR;
				default: return INVALID_CHAR~;
			}
			return type;
		case '&':
			switch
			{
				case self.must("&&&"): type = CT_AND_OP;
				case self.must("&&"):  type = AND;
				case self.must("&="):  type = BIT_AND_ASSIGN;
				case self.must("&"):   type = AMP;
				default: return INVALID_CHAR~;
			}
			return type;
		case '=':
			switch
			{
				case self.must("=>"):  type = IMPLIES;
				case self.must("=="):  type = EQEQ;
				case self.must("="):   type = EQ;
				default: return INVALID_CHAR~;
			}
			return type;
		case '>':
			switch
			{
				case self.must(">>="): type = SHR_ASSIGN;
				case self.must(">>"):  type = SHR_OP;
				case self.must(">="):  type = GREATER_EQ;
				case self.must(">]"):  type = RVEC;
				case self.must(">"):   type = GREATER;
				default: return INVALID_CHAR~;
			}
			return type;

		case '[':
			switch
			{
				case self.must("[<"):  type = LVEC;
				case self.must("["):   type = LBRACKET;
				default: return INVALID_CHAR~;
			}
			return type;

		case ']': self.advance()!; return RBRACKET;
		case '{': self.advance()!; return LBRACE;
		case '}': self.advance()!; return RBRACE;
		case '(': self.advance()!; return LPAREN;
		case ')': self.advance()!; return RPAREN;

		case '/':
			switch
			{
				case self.must("//"): self.scan_line_comment()!;  type = LINE_COMMENT;
				case self.must("/*"): self.scan_block_comment()!; type = BLOCK_COMMENT;
				case self.must("/="): type = DIV_ASSIGN;
				case self.must("/") : type = DIV;
				default: return INVALID_CHAR~;
			}
			return type;

		case '<':
			switch
			{
				case self.must("<*"):  self.scan_contract()!; type = CONTRACT;
				case self.must("<<="): type = SHL_ASSIGN;
				case self.must("<<"):  type = SHL_OP;
				case self.must("<="):  type = LESS_EQ;
				case self.must("<") :  type = LESS;
				default: return INVALID_CHAR~;
			}
			return type;

		case '$':
			switch
			{
				case self.must("$$"): return BUILTIN;
				case self.must("$"):  return self.lex_compile_time();
				default: return INVALID_CHAR~;
			}

		case '@':
		case '#':
			// A shebang is only a comment on the first line.
			if (self.pos == 0 && self.must("#!"))
			{
				self.scan_line_comment()!;
				return LINE_COMMENT;
			}
			self.advance()!;
			// On its own (`@` in `@[...]`, `#` in `#[...]`) it is punctuation.
			// Like the compiler: `@` starts an identifier before a letter or '_',
			// `#` only before a lowercase letter (after any '_'), so `#Foo` is
			// HASH + TYPE_IDENT and `@1` is AT + INTEGER.
			bool starts_ident;
			if (c == '@')
			{
				starts_ident = ascii::is_alpha(self.peek()) || self.peek() == '_';
			}
			else
			{
				sz i = 0;
				while (self.peek(i) == '_') i++;
				starts_ident = ascii::is_lower(self.peek(i));
			}
			if (!starts_ident) return c == '@' ? AT : HASH;
			return self.lex_at_or_hash_ident();

		case 'b':
		case 'x':
			switch
			{
				case self.must("b64\""): self.scan_until('"');
				case self.must("b64'"):  self.scan_until('\'');
				case self.must("b64`"):  self.scan_until('`');
				case self.must("x\""):   self.scan_until('"');
				case self.must("x'"):    self.scan_until('\'');
				case self.must("x`"):    self.scan_until('`');
				default: return self.lex_ident();
			}
			return BYTES;

		case '\'':
			self.scan_string();
			return CHAR_LITERAL;
		case '"':
		case '`':
			self.scan_string();
			return STRING;

		case '\n':
			self.advance()!;
			return EOL;

		default:
			if (is_digit(c)) return self.lex_number();
			if (is_ident(c)) return self.lex_ident();
			// Not the start of any token. Take the whole UTF-8 character, so a
			// multi-byte one (a pasted smart quote) is one INVALID token, not several.
			self.advance()!;
			while (!self.at_end() && (self.peek() & 0xC0) == 0x80) self.advance()!;
			return INVALID;
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

<*
 Scan up to and including `until`; bytes literals may span lines. Unterminated
 when the input ends first.
*>
fn void Lexer.scan_until(&self, char until)
{
	while (!self.at_end())
	{
		if (until == self.advance()!!) return;
	}
	self.unterminated = true;
}

<*
 Scan a string or char literal starting at its opening quote. `"…"` and `'…'`
 end at their line: one that reaches a newline (or the end of the input) has
 lost its closing quote, and stops there instead of swallowing the code that
 follows. A raw `` `…` `` string may span lines, and a doubled backtick in it
 is a literal backtick.
*>
fn void Lexer.scan_string(&self)
{
	char quote = self.peek();
	(void)self.advance(); // Opening quote
	while (!self.at_end())
	{
		char c = self.peek();
		if (quote == '`')
		{
			(void)self.advance();
			if (c != '`') continue;
			if (self.peek() != '`') return;
			(void)self.advance(); // `` is an escaped backtick
			continue;
		}
		if (c == '\n') break;
		(void)self.advance();
		if (c == quote) return;
		// An escape takes the next character with it, but never the line end.
		if (c == '\\' && !self.at_end() && self.peek() != '\n') (void)self.advance();
	}
	self.unterminated = true;
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
	String input = self.input;
	sz p = self.pos;
	sz depth = 1;
	while (p < input.len && depth != 0)
	{
		char c = input[p];
		if (c == '/' && p + 1 < input.len && input[p + 1] == '*')
		{
			depth++;
			p += 2;
			self.col += 2;
		}
		else if (c == '*' && p + 1 < input.len && input[p + 1] == '/')
		{
			depth--;
			p += 2;
			self.col += 2;
		}
		else
		{
			p++;
			self.track_byte(c);
		}
	}
	self.pos = p;
	if (depth != 0) self.unterminated = true;
}

fn void? Lexer.scan_contract(&self)
{
	String input = self.input;
	sz p = self.pos;
	while (p < input.len)
	{
		char c = input[p];
		if (c == '*' && p + 1 < input.len && input[p + 1] == '>')
		{
			self.pos = p + 2;
			self.col += 2;
			return;
		}
		p++;
		self.track_byte(c);
	}
	self.pos = p;
	self.unterminated = true;
}

fn TokenType Lexer.lex_number(&self)
{
	char c, prev;
	int i = 0;
	bool dot, expo;
	bool hex = self.peek() == '0' && (self.peek(1) == 'x' || self.peek(1) == 'X');
	while (!self.at_end() && (c = self.peek())
		&& (is_digit(c) || c == '-' || (i > 0 && (CHAR_CLASS[c] & CLASS_NUMBER)))
	)
	{
		// A sign belongs to the number only after its exponent marker: `e` in a
		// decimal literal, `p` in a hex one (where `e` is a digit: 0xFE-1).
		if ("+-".contains_char(c) && !(hex ? "pP" : "eE").contains_char(prev)) break;
		if (c == '.' && c == self.peek(1)) break;
		// Only one `.`, and none after the exponent: `90.0.to_radians()` is a
		// float followed by a member access.
		if (c == '.' && (dot || expo)) break;
		if (c == '.') dot = true;
		if ((hex ? "pP" : "eE").contains_char(c)) expo = true;
		(void)self.advance();
		prev = c;
		i++;
	}

	return number::classify(self.lexeme());
}

fn TokenType Lexer.lex_ident(&self)
{
	self.skip_ident_chars();

	String str = self.lexeme();
	// Keywords are all lowercase: anything else is a plain identifier of some kind.
	if (!(CHAR_CLASS[str[0]] & CLASS_LOWER)) return ident::classify(str);
	switch (str)
	{
		// Top-Level Explicit Keywords
		case "alias":     return ALIAS;
		case "attrdef":   return ATTRDEF;
		case "attrmacro": return ATTRMACRO;
		case "bitstruct": return BITSTRUCT;
		case "const":     return CONST;
		case "constdef":  return CONSTDEF;
		case "constset":  return CONSTSET;
		case "enum":      return ENUM;
		case "faultdef":  return FAULTDEF;
		case "fn":        return FUNC;
		case "import":    return IMPORT;
		case "interface": return INTERFACE;
		case "macro":     return MACRO;
		case "module":    return MODULE;
		case "typedef":   return TYPEDEF;
		case "struct":    return STRUCT;
		case "union":     return UNION;

		// Explicit Keywords
		case "any":       return ANY;
		case "asm":       return ASM;
		case "assert":    return ASSERT;
		case "break":     return BREAK;
		case "case":      return CASE;
		case "catch":     return CATCH;
		case "continue":  return CONTINUE;
		case "default":   return DEFAULT;
		case "defer":     return DEFER;
		case "do":        return DO;
		case "else":      return ELSE;
		case "false":     return FALSE;
		case "for":       return FOR;
		case "foreach":   return FOREACH;
		case "foreach_r": return FOREACH_R;
		case "if":        return IF;
		case "lengthof":  return LENGTHOF;
		case "nextcase":  return NEXTCASE;
		case "null":      return NULL;
		case "return":    return RETURN;
		case "static":    return STATIC;
		case "switch":    return SWITCH;
		case "true":      return TRUE;
		case "try":       return TRY;
		case "var":       return VAR;
		case "while":     return WHILE;

		case "extern":    return EXTERN;
		case "inline":    return INLINE;
		case "tlocal":    return TLOCAL;

		// Base Types
		case "void":      return VOID;
		case "bool":      return BOOL;
		case "char":      return CHAR;
		case "ichar":     return ICHAR;
		case "short":     return SHORT;
		case "ushort":    return USHORT;
		case "int":       return INT;
		case "uint":      return UINT;
		case "long":      return LONG;
		case "ulong":     return ULONG;
		case "int128":    return INT128;
		case "uint128":   return UINT128;
		case "iptr":      return IPTR;
		case "uptr":      return UPTR;
		case "sz":        return ISZ;
		case "usz":       return USZ;
		case "float":     return FLOAT;
		case "double":    return DOUBLE;
		case "float16":   return FLOAT16;
		case "bfloat":    return BFLOAT;
		case "float128":  return FLOAT128;
		case "fault":     return FAULT;
		case "typeid":    return TYPEID;
		case "untypedlist": return UNTYPEDLIST;

		default:
			return IDENT; // lowercase first, not a keyword
	}
}

fn TokenType Lexer.lex_compile_time(&self)
{
	self.skip_ident_chars();

	String str = self.lexeme();
	switch (str)
	{
		// Compile time keywords (C3 0.8)
		case "$assert":     return CT_ASSERT;
		case "$case":       return CT_CASE;
		case "$default":    return CT_DEFAULT;
		case "$defined":    return CT_DEFINED;
		case "$echo":       return CT_ECHO;
		case "$else":       return CT_ELSE;
		case "$embed":      return CT_EMBED;
		case "$endfor":     return CT_ENDFOR;
		case "$endforeach": return CT_ENDFOREACH;
		case "$endif":      return CT_ENDIF;
		case "$endswitch":  return CT_ENDSWITCH;
		case "$error":      return CT_ERROR;
		case "$eval":       return CT_EVAL;
		case "$exec":       return CT_EXEC;
		case "$expand":     return CT_EXPAND;
		case "$feat":       return CT_FEAT;
		case "$feature":    return CT_FEATURE;
		case "$for":        return CT_FOR;
		case "$foreach":    return CT_FOREACH;
		case "$if":         return CT_IF;
		case "$include":    return CT_INCLUDE;
		case "$reflect":    return CT_REFLECT;
		case "$stringify":  return CT_STRINGIFY;
		case "$switch":     return CT_SWITCH;
		case "$Typefrom":   return CT_TYPEFROM;
		case "$Typeof":     return CT_TYPEOF;
		case "$vaarg":      return CT_VAARG;

		default:
			return ident::classify(str);
	}
}

fn TokenType Lexer.lex_at_or_hash_ident(&self)
{
	self.skip_ident_chars();

	return ident::classify(self.lexeme());
}

struct ContractLexer
{
	Splitter splitter;
	Lexer    lexer;
	bool     lexer_init;
	<* intro is only available after the entire contract is lexed *>
	String   intro;
}

<*
 @require contract.len >= 4 : "Contract must contain at least 4 chars"
*>
fn ContractLexer* ContractLexer.init(&self, String contract)
{
	*self = {
		.splitter   = contract[2:^4].tokenize_all("\n", true),
		.lexer      = {},
		.lexer_init = false,
	};
	return self;
}

fn Token? ContractLexer.next(&self)
{
	if (!self.lexer_init)
	{
		sz pos;
		pos = self.splitter.current;
		while (try next_line = self.splitter.next())
		{
			if (next_line.trim().starts_with("@"))
			{
				self.intro = self.splitter.string[:pos];
				self.lexer.init(self.splitter.string[pos..], emit_eol: true);
				self.lexer_init = true;
				break;
			}
			pos = self.splitter.current;
		}
	}
	return self.lexer.next();
}

module c3::lexer::number;

<*
 Number literal states, following c3c: an `_` must sit between two digits, a
 base prefix needs at least one digit, integer suffixes are `u`, `l`, `ul`,
 `ll` and `ull` (any case), and reals take an optional `f`/`d` (any case).
*>
enum NumberState : char (TokenType type) @private
{
	ERROR      { INVALID },
	INIT       { INVALID },
	INTEGER    { INTEGER },
	ZERO       { INTEGER },
	HEXSTART   { INVALID },  // "0x" with no digit yet
	HEXINT     { INTEGER },
	OCTSTART   { INVALID },
	OCTINT     { INTEGER },
	BINSTART   { INVALID },
	BININT     { INTEGER },
	INT_US     { INVALID },  // "_" inside a decimal integer
	HEX_US     { INVALID },
	OCT_US     { INVALID },
	BIN_US     { INVALID },
	SUFFIX_U   { INTEGER },  // u
	SUFFIX_L   { INTEGER },  // l
	SUFFIX_UL  { INTEGER },  // ul
	SUFFIX_END { INTEGER },  // ll, ull
	REAL       { REAL },     // after a real suffix
	DOT        { REAL },     // INT "." (c3c accepts `1.`)
	INTDEC     { REAL },     // INT "." INT
	DEC_US     { INVALID },  // "_" inside the fraction
	EDIGITS    { REAL },     // Exponent digits
	HEXDEC     { INVALID },  // Hexadecimal "decimal": HEXINT "." HEXINT
	HEXDEC_US  { INVALID },
	EXPONENT   { INVALID },  // E-notation [eEpP]
	EXPSIGN    { INVALID },  // Exponent sign: + or -
}

const NumberState[char::max+1][*] TRANSITIONS @private = {
	[NumberState.INIT] = {
		['1'..'9'] = INTEGER,
		['0']      = ZERO,
		['+']      = INIT,
		['-']      = INIT,
	},
	[NumberState.INTEGER] = {
		['0'..'9'] = INTEGER,
		['_']      = INT_US,
		['e']      = EXPONENT,  ['E'] = EXPONENT,
		['d']      = REAL,      ['f'] = REAL,
		['D']      = REAL,      ['F'] = REAL,
		['u']      = SUFFIX_U,  ['U'] = SUFFIX_U,
		['l']      = SUFFIX_L,  ['L'] = SUFFIX_L,
		['.']      = DOT,
	},
	[NumberState.ZERO] = {
		['0'..'9'] = INTEGER,
		['_']      = INT_US,
		['b']      = BINSTART,  ['B'] = BINSTART,
		['o']      = OCTSTART,  ['O'] = OCTSTART,
		['x']      = HEXSTART,  ['X'] = HEXSTART,
		['e']      = EXPONENT,  ['E'] = EXPONENT,
		['d']      = REAL,      ['f'] = REAL,
		['D']      = REAL,      ['F'] = REAL,
		['u']      = SUFFIX_U,  ['U'] = SUFFIX_U,
		['l']      = SUFFIX_L,  ['L'] = SUFFIX_L,
		['.']      = DOT,
	},
	[NumberState.INT_US] = {
		['0'..'9'] = INTEGER,
		['.']      = DOT,
	},
	[NumberState.HEXSTART] = {
		['0'..'9'] = HEXINT,
		['a'..'f'] = HEXINT,
		['A'..'F'] = HEXINT,
	},
	[NumberState.HEXINT] = {
		['0'..'9'] = HEXINT,
		['a'..'f'] = HEXINT,
		['A'..'F'] = HEXINT,
		['_']      = HEX_US,
		['p']      = EXPONENT,  ['P'] = EXPONENT,
		['u']      = SUFFIX_U,  ['U'] = SUFFIX_U,
		['l']      = SUFFIX_L,  ['L'] = SUFFIX_L,
		['.']      = HEXDEC,
	},
	[NumberState.HEX_US] = {
		['0'..'9'] = HEXINT,
		['a'..'f'] = HEXINT,
		['A'..'F'] = HEXINT,
	},
	[NumberState.OCTSTART] = {
		['0'..'7'] = OCTINT,
	},
	[NumberState.OCTINT] = {
		['0'..'7'] = OCTINT,
		['_']      = OCT_US,
		['u']      = SUFFIX_U,  ['U'] = SUFFIX_U,
		['l']      = SUFFIX_L,  ['L'] = SUFFIX_L,
	},
	[NumberState.OCT_US] = {
		['0'..'7'] = OCTINT,
	},
	[NumberState.BINSTART] = {
		['0'..'1'] = BININT,
	},
	[NumberState.BININT] = {
		['0'..'1'] = BININT,
		['_']      = BIN_US,
		['u']      = SUFFIX_U,  ['U'] = SUFFIX_U,
		['l']      = SUFFIX_L,  ['L'] = SUFFIX_L,
	},
	[NumberState.BIN_US] = {
		['0'..'1'] = BININT,
	},
	[NumberState.SUFFIX_U] = {
		['l']      = SUFFIX_UL, ['L'] = SUFFIX_UL,
	},
	[NumberState.SUFFIX_L] = {
		['l']      = SUFFIX_END, ['L'] = SUFFIX_END,
	},
	[NumberState.SUFFIX_UL] = {
		['l']      = SUFFIX_END, ['L'] = SUFFIX_END,
	},
	[NumberState.DOT] = {
		['0'..'9'] = INTDEC,
		['e']      = EXPONENT, ['E'] = EXPONENT,
		['d']      = REAL,     ['f'] = REAL,
		['D']      = REAL,     ['F'] = REAL,
	},
	[NumberState.INTDEC] = {
		['0'..'9'] = INTDEC,
		['_']      = DEC_US,
		['e']      = EXPONENT, ['E'] = EXPONENT,
		['d']      = REAL,     ['f'] = REAL,
		['D']      = REAL,     ['F'] = REAL,
	},
	[NumberState.DEC_US] = {
		['0'..'9'] = INTDEC,
	},
	[NumberState.HEXDEC] = {
		['0'..'9'] = HEXDEC,
		['a'..'f'] = HEXDEC,
		['A'..'F'] = HEXDEC,
		['_']      = HEXDEC_US,
		['p']      = EXPONENT,  ['P'] = EXPONENT,
	},
	[NumberState.HEXDEC_US] = {
		['0'..'9'] = HEXDEC,
		['a'..'f'] = HEXDEC,
		['A'..'F'] = HEXDEC,
	},
	[NumberState.EXPONENT] = {
		['0'..'9'] = EDIGITS,
		['+']      = EXPSIGN,
		['-']      = EXPSIGN,
	},
	[NumberState.EDIGITS] = {
		['0'..'9'] = EDIGITS,
		['d']      = REAL, ['f'] = REAL,
		['D']      = REAL, ['F'] = REAL,
	},
	[NumberState.EXPSIGN] = {
		['0'..'9'] = EDIGITS,
	},
};

fn TokenType classify(String s)
{
	NumberState state = INIT;
	foreach (c: s) state = TRANSITIONS[state][c];
	return state.type;
}

module c3::lexer::ident;

import c3::lexer;

// classify() derives TYPE_IDENT / CONST_IDENT by adding an offset to the base token.
$assert TokenType.IDENT.ordinal + 1      == TokenType.TYPE_IDENT.ordinal : "classify() relies on this TokenType order";
$assert TokenType.IDENT.ordinal + 2      == TokenType.CONST_IDENT.ordinal : "classify() relies on this TokenType order";
$assert TokenType.CT_IDENT.ordinal + 1   == TokenType.CT_TYPE_IDENT.ordinal : "classify() relies on this TokenType order";
$assert TokenType.CT_IDENT.ordinal + 2   == TokenType.CT_CONST_IDENT.ordinal : "classify() relies on this TokenType order";
$assert TokenType.AT_IDENT.ordinal + 1   == TokenType.AT_TYPE_IDENT.ordinal : "classify() relies on this TokenType order";
$assert TokenType.AT_IDENT.ordinal + 2   == TokenType.AT_CONST_IDENT.ordinal : "classify() relies on this TokenType order";

<*
 Classify an identifier with an optional `$`, `@` or `#` prefix:
 after the prefix and any leading '_', a lowercase letter makes an IDENT, an
 uppercase one a CONST_IDENT, or a TYPE_IDENT once a lowercase letter follows.
 A digit first, or only '_', is INVALID.
*>
fn TokenType classify(String s)
{
	// A lone '_' is its own token in the compiler.
	if (s == "_") return UNDERSCORE;

	sz i = 0;
	TokenType base = IDENT;
	if (s.len)
	{
		switch (s[0])
		{
			case '$': base = CT_IDENT; i = 1;
			case '#': base = HASH_IDENT; i = 1;
			case '@': base = AT_IDENT; i = 1;
		}
	}
	while (i < s.len && s[i] == '_') i++;
	if (i == s.len) return INVALID;

	char first = lexer::CHAR_CLASS[s[i]];
	if (!(first & (lexer::CLASS_LOWER | lexer::CLASS_UPPER))) return INVALID;

	bool lower = (first & lexer::CLASS_LOWER) != 0;
	bool has_lower;
	for (i++; i < s.len; i++)
	{
		char k = lexer::CHAR_CLASS[s[i]];
		if (!(k & lexer::CLASS_IDENT)) return INVALID;
		has_lower |= (k & lexer::CLASS_LOWER) != 0;
	}

	// The compiler has no #Type / #CONST tokens.
	if (base == HASH_IDENT) return lower ? HASH_IDENT : INVALID;
	if (lower) return base;
	return TokenType::from_ordinal(base.ordinal + (has_lower ? 1 : 2));
}
