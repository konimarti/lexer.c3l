module pratt;

import std::io, std::collections::list;
import c3::lexer;

fn void print_repl() @inline
{
	io::print("pratt> ");
}

fn void main() => @pool()
{
	io::printfn("Pratt REPL -- print 'q' to quit.");
	print_repl();
	while (try s = io::treadline(io::stdin()))
	{
		if (s == "q") break;
		PrattParser p;
		p.init(s);
		if (try e = p.parse())
		{
			io::printfn("eval: %s", e);
			if (!p.lexer.at_end())
			{
				io::print("remaining tokens:");
				while (!p.lexer.at_end())
				{
					io::printf(" %s", p.lexer.next() ?? (Token){});
				}
			}
		}
		else
		{
			io::printfn(" -- Parse() failed");
		}
		print_repl();
	}
}

struct TestCase
{
	String input;
	String want;
}

fn void test_pratt_parser() @test
{
	TestCase[] test = {
		{ "a", "(ExprIdent <IDENT> a)" },
	};
	foreach (tc: test)
	{
		PrattParser p;
		p.init(tc.input);
		String expr = string::tformat("%s", p.parse()!!);
		assert(expr == tc.want, "Pratt Parser Test failed: got=%s, want=%s", expr, tc.want);
	}
}

struct PrattParser
{
	Lexer lexer;
	Token tok;
}

fn void PrattParser.init(&self, String s)
{
	self.lexer.init(s);
	self.tok = self.lexer.next() ?? {};
}

fn Token PrattParser.peek(&self) => self.tok;
fn Token PrattParser.consume(&self)
{
	Token tok = self.tok;
	self.tok = self.lexer.next() ?? {};
	return tok;
}

fn bool PrattParser.match(&self, TokenType expect)
{
	if (self.peek().type != expect) return false;
	(void)self.consume();
	return true;
}

fn Expr*? PrattParser.parse(&self) => parse_expr(self, 0)!;

fn Expr*? parse_expr(PrattParser *p, int min_bp = Precedence.NONE)
{
	Token tok = p.consume();

	Parselet parselet = pratt_table[tok.type];
	assert(parselet.prefix, "Pratt: No prefix parselet for Token %s", tok);

	Expr *left = parselet.prefix(p, tok)!;

	while (true)
	{
		parselet = pratt_table[p.peek().type];
		if (parselet.infix == null || min_bp >= parselet.binding_power) break;

		tok = p.consume();
		left = parselet.infix(p, left, tok)!;
	}

	return left;
}

/*
 Parslets
*/

alias PrefixParselet = fn Expr*? (PrattParser *p, Token tok);
alias InfixParselet  = fn Expr*? (PrattParser *p, Expr *left, Token tok);

enum Assoc : const inline char
{
	NONE  = 0,
	RIGHT = 0,
	LEFT  = 1,
}

enum Precedence : inline char
{
	NONE,
	ASSIGNMENT,     // = "= /= %= += etc.
	TERNARY,        // ?: ? ??
	OR,             // || |||
	AND,            // && &&&
	RELATIONAL,     // < > <= >= == !=
	ADDITIVE,       // + - +++
	BIT,            // ~ | &
	SHIFT,          // << >>
	MULTIPLICATIVE, // * / %
	UNARY,          // ! - + ~ * & prefix ++/-- (type)
	CALL,           // . () [] postfix ++ -- !! !
	PRIMARY,
}

struct Parselet
{
	PrefixParselet prefix;
	InfixParselet  infix;
	int            binding_power;
	Assoc          assoc;
}

Parselet[*] pratt_table = {
	[TokenType.INVALID]      = {},

	// Precedence.ASSIGNMENT
	[TokenType.EQ]               = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.PLUS_ASSIGN]      = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.MINUS_ASSIGN]     = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.MULT_ASSIGN]      = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.MOD_ASSIGN]       = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.DIV_ASSIGN]       = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.BIT_XOR_ASSIGN]   = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.BIT_AND_ASSIGN]   = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.BIT_OR_ASSIGN]    = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.SHR_ASSIGN]       = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.SHL_ASSIGN]       = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },
	[TokenType.CT_CONCAT_ASSIGN] = { null,                    &parse_binary,           Precedence.ASSIGNMENT,     Assoc.LEFT  },

	// Precedence.TERNARY
	[TokenType.QUESTION]         = { null,                    &parse_ternary,          Precedence.TERNARY,        Assoc.RIGHT },
	[TokenType.QUESTQUEST]       = { null,                    null /*TODO*/,           Precedence.TERNARY,        Assoc.RIGHT },
	[TokenType.ELVIS]            = { null,                    null /*TODO*/,           Precedence.TERNARY,        Assoc.RIGHT },
	[TokenType.CT_TERNARY]       = { null,                    &parse_ternary,          Precedence.TERNARY,        Assoc.RIGHT },

	// Precedence.OR
	[TokenType.OR]               = { null,                    &parse_binary,           Precedence.OR,             Assoc.LEFT  },
	[TokenType.CT_OR_OP]         = { null,                    &parse_binary,           Precedence.OR,             Assoc.LEFT  },

	// Precedence.AND
	[TokenType.AND]              = { &parse_unary,            &parse_binary,           Precedence.AND,            Assoc.LEFT  },
	[TokenType.CT_AND_OP]        = { &parse_unary,            &parse_binary,           Precedence.AND,            Assoc.LEFT  },

	// Precedence.RELATIONAL
	[TokenType.EQEQ]             = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },
	[TokenType.NOT_EQUAL]        = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },
	[TokenType.GREATER]          = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },
	[TokenType.GREATER_EQ]       = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },
	[TokenType.LESS]             = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },
	[TokenType.LESS_EQ]          = { null,                    &parse_binary,           Precedence.RELATIONAL,     Assoc.LEFT  },

	// Precedence.ADDITIVE
	[TokenType.PLUS]             = { &parse_unary,            &parse_binary,           Precedence.ADDITIVE,       Assoc.LEFT  },
	[TokenType.MINUS]            = { &parse_unary,            &parse_binary,           Precedence.ADDITIVE,       Assoc.LEFT  },
	[TokenType.CT_CONCAT_OP]     = { null,                    &parse_binary,           Precedence.ADDITIVE,       Assoc.LEFT  },

	// Precedence.BIT
	[TokenType.BIT_XOR]          = { null /*TODO*/,           &parse_binary,           Precedence.BIT,            Assoc.LEFT  },
	[TokenType.BIT_OR]           = { null,                    &parse_binary,           Precedence.BIT,            Assoc.LEFT  },
	[TokenType.AMP]              = { &parse_unary,            &parse_binary,           Precedence.BIT,            Assoc.LEFT  },

	// Precedence.SHIFT
	[TokenType.SHL_OP]           = { null,                    &parse_binary,           Precedence.SHIFT,          Assoc.LEFT  },
	[TokenType.SHR_OP]           = { null,                    &parse_binary,           Precedence.SHIFT,          Assoc.LEFT  },

	// Precedence.MULTIPLICAT    IVE
	[TokenType.DIV]              = { null,                    &parse_binary,           Precedence.MULTIPLICATIVE, Assoc.LEFT  },
	[TokenType.MOD]              = { null,                    &parse_binary,           Precedence.MULTIPLICATIVE, Assoc.LEFT  },
	[TokenType.STAR]             = { &parse_unary,            &parse_binary,           Precedence.MULTIPLICATIVE, Assoc.LEFT  },

	// Precedence.CALL
	[TokenType.PLUSPLUS]         = { &parse_unary,            &parse_postfix,          Precedence.CALL,           Assoc.LEFT  },
	[TokenType.MINUSMINUS]       = { &parse_unary,            &parse_postfix,          Precedence.CALL,           Assoc.LEFT  },
	[TokenType.LPAREN]           = { &parse_group,            &parse_call,             Precedence.CALL,           Assoc.LEFT  },
	[TokenType.BANGBANG]         = { &parse_unary,            null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },
	[TokenType.LBRACKET]         = { null,                    null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },
	[TokenType.LBRACE]           = { null /*TODO*/,           null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },
	[TokenType.DOT]              = { null,                    null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },
	[TokenType.BANG]             = { &parse_unary,            null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },
	[TokenType.BIT_NOT]          = { &parse_unary,            null /*TODO*/,           Precedence.CALL,           Assoc.LEFT  },

	// [TokenType.FIRST_KEYWORD..T  okenType.FIRST_NON_TYPE_KEYWORD]
	//                              = { &parse_type_ident,       null,                    NONE,           Assoc.NONE  },

	[TokenType.BYTES]            = { &parse_bytes,            null,                    Precedence.NONE,           Assoc.NONE  },
	[TokenType.TRUE]             = { &parse_bool,             null,                    Precedence.NONE,           Assoc.NONE  },
	[TokenType.FALSE]            = { &parse_bool,             null,                    Precedence.NONE,           Assoc.NONE  },
	[TokenType.NULL]             = { &parse_null,             null,                    Precedence.NONE,           Assoc.NONE  },
	// [TokenType.LENGTHOF]         = { &parse_lengthof,         null,                    NONE,           Assoc.NONE  },
	[TokenType.INTEGER]          = { &parse_integer,          null,                    Precedence.NONE,           Assoc.NONE  },
	[TokenType.REAL]             = { &parse_double,           null,                    Precedence.NONE,           Assoc.NONE  },
	[TokenType.BUILTIN]          = { &parse_builtin,          null,                    Precedence.NONE,           Assoc.NONE  },
	// [TokenType.CHAR_LITERAL]     = { &parse_char_lit,         null,                    NONE,           Assoc.NONE  },
	[TokenType.STRING]           = { &parse_string,           null,                    Precedence.NONE,           Assoc.NONE  },

	[TokenType.IDENT]            = { &parse_ident_start_expr, null,                    Precedence.NONE,           Assoc.NONE  },
	// [TokenType.TYPE_IDENT]       = { &parse_type_ident,       null,                    NONE,           Assoc.NONE  },
	// [TokenType.CT_IDENT]         = { &parse_ct_ident,         null,                    NONE,           Assoc.NONE  },
	[TokenType.CONST_IDENT]      = { &parse_ident,            null,                    Precedence.NONE,           Assoc.NONE  },
	// [TokenType.CT_CONST_IDENT]   = { &parse_ct_ident,         null,                    NONE,           Assoc.NONE  },
	// [TokenType.CT_TYPE_IDENT]    = { &parse_type_ident,       null,                    NONE,           Assoc.NONE  },
	// [TokenType.HASH_IDENT]       = { &parse_hash_ident,       null,                    NONE,           Assoc.NONE  },
	[TokenType.AT_IDENT]         = { &parse_ident,            null,                    Precedence.NONE,           Assoc.NONE  },
	// [TokenType.ELLIPSIS]         = { &parse_splat,            null,                    NONE,           Assoc.NONE  },
	// [TokenType.FN]               = { &parse_lambda,           null,                    NONE,           Assoc.NONE  },

	// TODO: CT_ALIGNOF .. CT_VATYPE

	[TokenType.EOF]          = {},
};

fn Expr* bad_expr(String msg)
{
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_BAD, .as.bad_expr = {msg} };
	return e;
}

fn bool token_is_some_ident(Token tok) @inline
{
	switch (tok.type)
	{
		case TokenType.TYPE_IDENT:
		case TokenType.IDENT:
		case TokenType.CONST_IDENT:
			return true;
		default:
			return false;
	}
}

fn Expr*? parse_builtin(PrattParser *p, Token tok)
{
	if (!token_is_some_ident(p.peek()))
	{
		return bad_expr("Unexpected '$$', did you mean to write a builtin?");
	}
	tok = p.consume(); // Consume '$$'

	Expr *e = mem::tnew(Expr);
	e.kind = (tok.type == TokenType.CONST_IDENT) ? EXPR_COMPILER_CONST : EXPR_BUILTIN;
	e.as.builtin_expr.ident = tok;
	return e;
}

fn Expr*? parse_integer(PrattParser *p, Token tok)
{
	ExprConst const_expr = { .const_kind = ConstKind.CONST_INTEGER, .ixx = tok };
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CONST, .as.const_expr = const_expr };
	return e;
}

fn Expr*? parse_double(PrattParser *p, Token tok)
{
	ExprConst const_expr = { .const_kind = ConstKind.CONST_FLOAT, .fxx = tok };
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CONST, .as.const_expr = const_expr };
	return e;
}

fn Expr*? parse_bool(PrattParser *p, Token tok)
{
	ExprConst const_expr = { .const_kind = ConstKind.CONST_BOOL, .b = (tok.type == TRUE) ? true : false};
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CONST, .as.const_expr = const_expr };
	return e;
}

fn Expr*? parse_null(PrattParser *p, Token tok)
{
	ExprConst const_expr = { .const_kind = ConstKind.CONST_POINTER, .ptr = 0 };
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CONST, .as.const_expr = const_expr };
	return e;
}

fn Expr*? parse_bytes(PrattParser *p, Token tok)
{
	ExprConst const_expr = { .const_kind = ConstKind.CONST_BYTES, .bytes = tok };
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CONST, .as.const_expr = const_expr };
	return e;
}

fn Expr*? parse_string(PrattParser *p, Token tok)
{
	ExprConst const_expr = { .const_kind = ConstKind.CONST_STRING, .bytes = tok };
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CONST, .as.const_expr = const_expr };
	return e;
}

<*
 ident := CONST_IDENT | IDENT
*>
fn Expr*? parse_ident(PrattParser *p, Token tok)
{
	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_IDENT, .as.ident_expr.ident = tok };
	return e;
}

struct Path (Printable)
{
	DString     path;
	List{Token} tokens;
}

fn void Path.free(&self)
{
	self.path.free();
	self.tokens.free();

}

fn usz? Path.to_format(&self, Formatter *f) @dynamic => f.printf("%s", self.path.str_view());

fn bool parse_path_prefix(PrattParser *p, Token *tok, Path **path_ref)
{
	if (tok.type != TokenType.IDENT
		|| p.peek().type != TokenType.SCOPE) return true;

	Path *path = mem::tnew(Path);
	path.path.tinit(); // TODO: Allocator??
	path.tokens.tinit(); // TODO: Allocator??
	path.path.append_string(tok.text);

	path.tokens.push(*tok);
	path.tokens.push(*tok = p.consume());
	path.tokens.push(*tok = p.consume());

	while (tok.type == TokenType.IDENT && p.peek().type == TokenType.SCOPE)
	{
		path.path.append_string("::");
		path.path.append_string(tok.text);

		path.tokens.push(*tok = p.consume());
		path.tokens.push(*tok = p.consume()); // Consume SCOPE
	}

	if (tok.type != TokenType.IDENT) {
		path.free();
		return false;
	}

	*path_ref = path;
	return true;
}

fn void test_parse_prefix() @test => @pool()
{
	String path_str = "very::looong::path::name";
	PrattParser p;
	p.init(path_str);

	Token tok = p.consume();

	assert(tok.type == TokenType.IDENT,
		"Beginning token should of type IDENT");

	assert(p.peek().type == TokenType.SCOPE,
		"Second token should of type SCOPE, but got %s", p.peek());

	Path *path;
	assert(parse_path_prefix(&p, &tok, &path));
	assert(tok.type == TokenType.IDENT, "got: %s", tok);
	assert(path, "Returned path should not be null");

	String got = path.path.str_view();
	assert(got == "very::looong::path", "got: %s, want: very::looong::path", got, path_str);
}

fn Expr*? parse_ident_start_expr(PrattParser *p, Token tok)
{
	Path *path;
	if (!parse_path_prefix(p, &tok, &path)) return bad_expr("parse_path_prefix failed");

	switch (tok.type)
	{
		case TokenType.IDENT:
		case TokenType.CONST_IDENT:
		case TokenType.AT_IDENT:
			Expr *expr = parse_ident(p, tok)!;
			expr.as.ident_expr.path = path;
			return expr;
		case TokenType.TYPE_IDENT:
			return parse_type_expr_with_path(p, tok, path);
		default:
			// Expected a type, function or constant.
			return bad_expr("Expected a type, function or constant.");
	}
}

<*
 type_expression_with_path ::= TYPE_IDENT initializer_list?
*>
fn Expr *parse_type_expr_with_path(PrattParser *p, Token tok, Path *path)
{
	TypeInfo *type;
	if (path)
	{
		type = mem::tnew(TypeInfo);
		type.unresolved.path = path;
		type.unresolved.name = tok;

		if (p.peek().type == TokenType.TYPE_IDENT) tok = p.consume();

		type = parse_type_with_base(p, type);

		if (p.peek().type == TokenType.QUESTION)
		{
			type.optional = p.consume();
			type.is_optional = true;
		}
	}
	else
	{
		type = parse_optional_type(p);
	}

	if (p.peek().type == TokenType.LBRACE)
	{
		// FIXME: needs to be implemented
		// return parse_type_compount_literal_expr_after_type(p, type);
		unreachable("not implemented yet");
	}

	Expr *expr = mem::tnew(Expr);
	expr.kind = EXPR_TYPEINFO;
	expr.as.type_expr = type;

	if (p.peek().type == TokenType.SCOPE)
	{
		return bad_expr("A type is never followed by '::', "
			"did you mean '.'?");
	}
	return expr;
}

fn TypeInfo* parse_optional_type(PrattParser *p) => parse_optional_type_maybe_generic(p, true);
fn TypeInfo* parse_optional_type_no_generic(PrattParser *p) => parse_optional_type_maybe_generic(p, false);

fn TypeInfo* parse_optional_type_maybe_generic(PrattParser *p, bool allow_generic)
{
	TypeInfo *info = parse_base_type(p)!!; // TODO: Propagate error
	info = parse_type_with_base_maybe_generic(c, info, allow_generic);
	if (p.peek().type == TokenType.QUESTION)
	{
		info.is_optional = true;
		info.optional = p.consume();
	}
	return info;
}

fn TypeInfo* parse_type_with_base(PrattParser *p, TypeInfo *type_info)
{
	return parse_type_with_base_maybe_generic(p, type_info, true);
}

<*
 type ::= base_type ( '*' | array_type_index | vector_type_index | generic_parameters )
*>
fn TypeInfo* parse_type_with_base_maybe_generic(PrattParser *p,
	TypeInfo *type_info, bool allow_generic)
{
	while (type_info && type_info.kind != TypeInfoKind.POISON)
	{
		switch (p.peek().type)
		{
			case TokenType.LBRACKET:
				type_info = parse_array_type_index(p, type_info);
			case TokenType.LVEC:
				type_info = parse_vector_type_index(p, type_info);
			case TokenType.LBRACE:
				if (!allow_generic) return type_info;
				type_info = parse_generic_type(p, type_info);
			case TokenType.STAR:
				Token tok = p.consume(); // Consume '*'
				switch (tok.type)
				{
					// FIXME: complete Switch Statement
					default:
				}
			default: return type_info;
		}
	}
	return type_info;
}

<*
 array_type_index ::= '[' (constant_expression | '*' )? ']'
*>
fn TypeInfo* parse_array_type_index(PrattParser *p, TypeInfo *type)
{
	Token open, close;

	if (p.peek().type == LBRACKET) open = p.consume(); // Consume '['

	if (p.peek().type == STAR)
	{
		TypeInfo *inferred_array = mem::tnew(TypeInfo);
		inferred_array.kind = TypeInfoKind.INFERRED_ARRAY;
		inferred_array.array.base = type;

		if (p.peek().type == RBRACKET) close = p.consume(); // Consume ']'
		return inferred_array;
	}

	if (p.peek().type == RBRACKET)
	{
		close = p.consume(); // Consume ']'
		TypeInfo *slice = mem::tnew(TypeInfo);
		slice.kind = TypeInfoKind.SLICE;
		slice.array.base = type;
		slice.array.len  = null;
		return slice;
	}

	TypeInfo *array = mem::tnew(TypeInfo);
	array.kind = TypeInfoKind.ARRAY;
	array.array.base = type;
	array.array.len  = parse_expr(p, Precedence.NONE)!!; // TODO: Propagate error?
	close = p.consume(); // Consume ']'
	assert(close.type == TokenType.RBRACKET);

	return array;
}

<*
 vector_type_index ::= '[<' (constant_expression | '*' ) '>]'
*>
fn TypeInfo* parse_vector_type_index(PrattParser *p, TypeInfo *type)
{
	TypeInfo *vector = mem::tnew(TypeInfo);
	vector.kind = TypeInfoKind.VECTOR;
	vector.array.base = type;

	Token open, close;
	open = p.consume(); // Consume '[<'
	assert(open.type == LVEC);

	if (p.peek().type == STAR)
	{
		Token star = p.consume(); // Consume '*'
		assert(star.type == STAR);
		vector.kind = TypeInfoKind.INFERRED_VECTOR;
	}
	else
	{
		vector.array.len = parse_expr(p, Precedence.NONE)!!; // TODO: Propagate error
	}

	close = p.consume();
	if (close.type != TokenType.RVEC) vector.kind = TypeInfoKind.POISON;

	if (p.peek().type == AT_IDENT)
	{
		p.consume(); // TODO: Here only @simd is allowed;
	}

	return vector;
}

fn TypeInfo* parse_generic_type(PrattParser *p, TypeInfo *type)
{
	TypeInfo *generic_type = mem::tnew(TypeInfo);
	generic_type.kind = TypeInfoKind.GENERIC;
	generic_type.generic.params.tinit();
	if (!parse_generic_expr_list(p, &generic_type.generic.params))
	{
		generic_type.kind = TypeInfoKind.POISON;
		generic_type.poison = "parse_generic_expr_list returned false";
	}
	generic_type.generic.base = type;
	return generic_type;
}

fn bool parse_generic_expr_list(PrattParser *p, List{Expr*} *params)
{
	if (p.peek().type == TokenType.LBRACE)
	{
		Expr *open = mem::tnew(Expr, { .kind = EXPR_TOKEN, .as.token_expr.token = p.consume() });
		params.push(open);
	}

	while (p.peek().type != TokenType.RBRACE)
	{
		if (try expr = parse_expr(p)) params.push(expr);
		if (p.peek().type == TokenType.COMMA)
		{
			Expr *comma = mem::tnew(Expr, { .kind = EXPR_TOKEN, .as.token_expr.token = p.consume() });
			params.push(comma);
		}
	}
	if (p.peek().type == TokenType.RBRACE)
	{
		Expr *close = mem::tnew(Expr, { .kind = EXPR_TOKEN, .as.token_expr.token = p.consume() });
		params.push(close);
		return true;
	}

	// TODO: Something's wrong here: exepected RBRACE
	return false;
}

<*
 grouping_expr ::= cast_expr | group_expr

 cast_expr ::= '(' type ')' expr
 group_expr ::= '(' expr ')'

 TODO: implement cast_expr
*>
fn Expr*? parse_group(PrattParser *p, Token tok)
{
	Token open, close;
	Expr *expr;

	open = tok;
	expr = parse_expr(p, Precedence.NONE)!;
	close = p.peek();

	if (p.peek().type != TokenType.RPAREN) return bad_expr("parse_group failed: expected RPAREN token");

	switch (expr.kind)
	{
		case EXPR_TYPEINFO:
			// Read compound literal
			if (p.peek().type == TokenType.LBRACE)
			{
				// FIXME: after implementing parse_type_expression_with_path
				// expr = parse_type_compound_literal_expr_after_type(p, expr);
				return expr;
			}

			// Create cast_expr

			Expr *new = mem::tnew(Expr);
			*new = { .kind = EXPR_CAST, .as.cast_expr = { open, expr, close} };
			return new;
		default:
			Expr *new = mem::tnew(Expr);
			*new = { .kind = EXPR_GROUP, .as.group_expr = { open, expr, close} };
			return new;
	}

}

fn Expr*? parse_unary(PrattParser *p, Token tok)
{
	Parselet parselet = pratt_table[tok.type];
	int next_bp = Precedence.UNARY;

	Expr* right = parse_expr(p, next_bp)!;

	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_UNARY, .as.unary_expr = { tok, right} };

	return e;
}

fn Expr*? parse_postfix(PrattParser *p, Expr *left, Token tok)
{
	Expr *e = mem::tnew(Expr);
	*e = { .kind = POSTFIX_EXPR, .as.p = { left, tok } };
	return e;
}

fn Expr*? parse_ternary(PrattParser *p, Expr *left, Token tok)
{
	Parselet parselet = pratt_table[tok.type];

	// If operator is right-associated, decrease binding power by one.
	int next_bp = parselet.binding_power - (parselet.assoc == Assoc.RIGHT ? 1 : 0);

	Expr* then_arm = parse_expr(p, 0)!;

	if (!p.match(TokenType.COLON))
	{
		abort("Expected ':'");
	}

	Expr* else_arm = parse_expr(p, next_bp)!;

	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_TERNARY, .as.ternary_expr = { left, then_arm, else_arm } };

	return e;
}

fn Expr*? parse_binary(PrattParser *p, Expr *left, Token tok)
{
	Parselet parselet = pratt_table[tok.type];

	// If operator is right-associated, decrease binding power by one.
	int next_bp = parselet.binding_power - (parselet.assoc == Assoc.RIGHT ? 1 : 0);

	Expr* right = parse_expr(p, next_bp)!;

	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_BINARY, .as.binary_expr = { left, tok, right} };

	return e;
}

fn Expr*? parse_call(PrattParser *p, Expr *left, Token tok)
{
	// `args` will be the comma-separated arguments
	List{Expr*} args;
	args.tinit(); // TODO: Allocator?

	// There might be no arguments
	if (!p.match(TokenType.RPAREN))
	{
		do {
			if (try arg = parse_expr(p, 0))
			{
				args.push(arg);
			}
			else
			{
				break;
			}
		} while (p.match(TokenType.COMMA));
	}

	if (!p.match(TokenType.RPAREN))
	{
		// TODO: Better throw error than abort
		abort("Unclosed parenthesis");
	}

	Expr *e = mem::tnew(Expr);
	*e = { .kind = EXPR_CALL, .as.call_expr = { left, args} };

	return e;
}


/*
 Expressions
*/

struct ExprBad
{
	String msg;
}

struct ExprBinary
{
	Expr *left;
	Token op;
	Expr *right;
}

struct ExprBuiltin
{
	Token ident;
}

struct ExprCall
{
	Expr        *func;
	List{Expr*} args;
}

struct ExprCast
{
	Token open;
	Expr  *type;
	Token close;
}

struct ExprGroup
{
	Token open;
	Expr  *expr;
	Token close;
}

struct ExprIdent
{
	Path* path;
	Token ident;
}

struct ExprTernary
{
	Expr *condition;
	Expr *then_arm;
	Expr *else_arm;
}

struct ExprToken
{
	Token token;
}

struct ExprUnary
{
	Token op;
	Expr *right;
}

enum TypeInfoKind
{
	POISON,
	IDENTIFIER,
	CT_IDENTIFIER,
	TYPEOF,
	VATYPE,
	EVALTYPE,
	TYPEFROM,
	ARRAY,
	VECTOR,
	INFERRED_ARRAY,
	INFERRED_VECTOR,
	SLICE,
	POINTER,
	GENERIC,
}

struct TypeInfo
{
	TypeInfoKind kind;
	// Type         *type; // parse_type_with_base(p, type)

	bool         is_optional;
	Token        optional;

	// TODO: Pack this into an union?
	union {
		struct unresolved {
			Path  *path;
			Token name;
		}
		Expr *unresolved_type_expr;
		struct array {
			TypeInfo *base;
			Expr *len;
		}
		TypeInfo *pointer;
		struct generic {
			TypeInfo    *base;
			List{Expr*} params;
		}
		String poison;
	}
}

struct PostfixExpression
{
	Expr *left;
	Token op;
}

enum ConstKind
{
	CONST_FLOAT,
	CONST_INTEGER,
	CONST_BOOL,
	CONST_POINTER,
	CONST_BYTES,
	CONST_STRING,
}

struct ExprConst (Printable)
{
	ConstKind const_kind;
	union
	{
		Token fxx;
		Token ixx;
		bool  b;
		uptr  ptr;
		Token bytes;
	}
}

fn usz? ExprConst.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	switch (self.const_kind)
	{
		case CONST_FLOAT:   n += f.printf("%s", self.fxx)!;
		case CONST_INTEGER: n += f.printf("%s", self.ixx)!;
		case CONST_BOOL:    n += f.printf("<%s>", self.b)!;
		case CONST_POINTER: n += f.printf("%s", self.ptr)!;
		case CONST_STRING:
		case CONST_BYTES:   n += f.printf("%s", self.bytes)!;
	}
	return n;
}

enum ExprKind
{
	EXPR_BAD,
	EXPR_BINARY,
	EXPR_BUILTIN,
	EXPR_CALL,
	EXPR_CAST,
	EXPR_COMPILER_CONST,
	EXPR_CONST,
	EXPR_GROUP,
	EXPR_IDENT,
	EXPR_UNARY,
	EXPR_TERNARY,
	EXPR_TOKEN,
	EXPR_TYPEINFO,

	POSTFIX_EXPR,
}

struct Expr (Printable)
{
	ExprKind kind;
	union as {
		ExprBad     bad_expr;
		ExprBinary  binary_expr;
		ExprBuiltin builtin_expr;
		ExprCall    call_expr;
		ExprCast    cast_expr;
		ExprConst   const_expr;
		ExprGroup   group_expr;
		ExprIdent   ident_expr;
		ExprTernary ternary_expr;
		ExprToken   token_expr;
		TypeInfo    *type_expr;
		ExprUnary   unary_expr;

		PostfixExpression p;
	}
}

fn usz? Expr.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	switch (self.kind)
	{
		case EXPR_BAD:      n += f.printf("(ExprBad %s)", self.as.bad_expr.msg)!;
		case EXPR_BINARY:   n += f.printf("(%s %s %s)", self.as.binary_expr.left, self.as.binary_expr.op, self.as.binary_expr.right)!;
		case EXPR_CALL:     n += f.printf("(ExprCall %s( %s ))", self.as.call_expr.func, self.as.call_expr.args)!;
		case EXPR_COMPILER_CONST:
		case EXPR_BUILTIN:  n += f.printf("(ExprBuiltin %s)", self.as.builtin_expr.ident)!;
		case EXPR_CAST:     n += f.printf("(ExprCast (%s))", self.as.cast_expr.type)!;
		case EXPR_CONST:    n += f.printf("(ExprConst %s)", self.as.const_expr)!;
		case EXPR_GROUP:    n += f.printf("(ExprGroup %s %s %s))", self.as.group_expr.open, self.as.group_expr.expr, self.as.group_expr.close)!;
		case EXPR_IDENT:    n += f.printf("(ExprIdent %s)", self.as.ident_expr.ident)!;
		case EXPR_TERNARY:  n += f.printf("(%s ? %s : %s)", self.as.ternary_expr.condition, self.as.ternary_expr.then_arm, self.as.ternary_expr.else_arm)!;
		case EXPR_TOKEN:    n += f.printf("(ExprToken %s)", self.as.token_expr.token)!;
		case EXPR_TYPEINFO: n += f.printf("<not implemented yet>")!;
		case EXPR_UNARY:    n += f.printf("( %s %s )", self.as.unary_expr.op, self.as.unary_expr.right)!;

		case POSTFIX_EXPR:  n += f.printf("( %s %s )", self.as.p.left, self.as.p.op)!;
	}
	return n;
}

