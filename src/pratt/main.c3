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
			io::printn(e);
		}
		else
		{
			io::printfn(" -- Parse() failed");
		}
		print_repl();
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

fn Expr*? parse_expr(PrattParser *p, int min_bp)
{
	Token tok = p.consume();

	Parselet parselet = pratt_table[tok.type];
	assert(parselet.prefix, "Pratt: No prefix parselet for Token %s", tok);

	Expr *left = parselet.prefix(p, tok)!;

	while (!p.lexer.at_end())
	{
		parselet = pratt_table[p.peek().type];
		if (parselet.infix == null || min_bp >= parselet.infix_bp) break;

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

enum Precedence : const inline int
{
	COMPARISON =  5,
	ASSIGNMENT = 10,
	CONDITION  = 20,
	SUM        = 30,
	PRODUCT    = 40,
	EXPONENT   = 50,
	PREFIX     = 60,
	POSTFIX    = 70,
	CALL       = 80,
}

struct Parselet
{
	PrefixParselet prefix;
	InfixParselet  infix;
	int            prefix_bp;
	int            infix_bp;
	Assoc          assoc;
}

Parselet[*] pratt_table = {
	[TokenType.LESS..TokenType.CT_OR_OP]
	                    = { null,          &parse_binary,  0,  5, Assoc.LEFT },
	[TokenType.EQ..TokenType.CT_CONCAT_ASSIGN]
	                    = { null,          &parse_assign,  0, 10, Assoc.RIGHT },
	[TokenType.STRING..TokenType.CT_CONST_IDENT]
	                    = { &parse_ident,  null,           0,  0, Assoc.NONE },
	[TokenType.INTEGER] = { &parse_number, null,           0,  0, Assoc.NONE },
	[TokenType.REAL]    = { &parse_number, null,           0,  0, Assoc.NONE },
	[TokenType.PLUS]    = { &parse_unary,  &parse_binary, 60, 30, Assoc.LEFT },
	[TokenType.MINUS]   = { &parse_unary,  &parse_binary, 60, 30, Assoc.LEFT },
	[TokenType.STAR]    = { null,          &parse_binary,  0, 40, Assoc.LEFT },
	[TokenType.DIV]     = { null,          &parse_binary,  0, 40, Assoc.LEFT },
	[TokenType.LPAREN]  = { &parse_group,  &parse_call,    0, 80, Assoc.LEFT },
	[TokenType.EOF]     = {},
};

fn Expr*? parse_number(PrattParser *p, Token tok)
{
	Expr *e = mem::tnew(Expr);
	*e = { .kind = NUMBER_EXPR, .as.n = tok };
	return e;
}

fn Expr*? parse_ident(PrattParser *p, Token tok)
{
	Expr *e = mem::tnew(Expr);
	*e = { .kind = IDENT_EXPR, .as.i = tok };
	return e;
}

fn Expr*? parse_group(PrattParser *p, Token tok)
{
	Expr *e = parse_expr(p, 0)!;
	if (!p.match(TokenType.RPAREN))
	{
		// TODO: Better throw error than abort
		abort("Unclosed parenthesis");
	}
	return e;
}

fn Expr*? parse_unary(PrattParser *p, Token tok)
{
	Parselet parselet = pratt_table[tok.type];
	int next_bp = parselet.prefix_bp;

	Expr* right = parse_expr(p, next_bp)!;

	Expr *e = mem::tnew(Expr);
	*e = { .kind = UNARY_EXPR, .as.u = { tok, right} };

	return e;
}

fn Expr*? parse_assign(PrattParser *p, Expr *left, Token tok)
{
	assert(left.kind == IDENT_EXPR,
		"Left-hand side of assignment needs to be a name");

	Parselet parselet = pratt_table[tok.type];

	// If operator is right-associated, decrease binding power by one.
	int next_bp = parselet.infix_bp - (parselet.assoc == Assoc.RIGHT ? 1 : 0);

	Expr* right = parse_expr(p, next_bp)!;

	Expr *e = mem::tnew(Expr);
	*e = { .kind = ASSIGN_EXPR, .as.a = { left.as.i, right} };

	return e;
}


fn Expr*? parse_binary(PrattParser *p, Expr *left, Token tok)
{
	Parselet parselet = pratt_table[tok.type];

	// If operator is right-associated, decrease binding power by one.
	int next_bp = parselet.infix_bp - (parselet.assoc == Assoc.RIGHT ? 1 : 0);

	Expr* right = parse_expr(p, next_bp)!;

	Expr *e = mem::tnew(Expr);
	*e = { .kind = BINARY_EXPR, .as.b = { tok, left, right} };

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
	*e = { .kind = CALL_EXPR, .as.c = { left, args} };

	return e;
}


/*
 Expressions
*/

alias NumberExpression = Token;
alias IdentExpression = Token;

struct UnaryExpression
{
	Token op;
	Expr *right;
}

struct AssignExpression
{
	Token op;
	Expr *right;
}

struct BinaryExpression
{
	Token op;
	Expr *left;
	Expr *right;
}

struct CallExpression
{
	Expr*       func;
	List{Expr*} args;
}

enum ExprKind
{
	// Prefix Parselets
	NUMBER_EXPR,
	IDENT_EXPR,
	UNARY_EXPR,

	// Infix Parselets
	ASSIGN_EXPR,
	BINARY_EXPR,
	CALL_EXPR,
}

struct Expr (Printable)
{
	ExprKind kind;
	union as {
		NumberExpression n;
		IdentExpression  i;
		UnaryExpression  u; // Prefix expressions
		AssignExpression a;
		BinaryExpression b; // Infix expressions
		CallExpression   c;
	}
}

fn usz? Expr.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	switch (self.kind)
	{
		case NUMBER_EXPR: n += f.printf("%s", self.as.n)!;
		case IDENT_EXPR:  n += f.printf("%s", self.as.i)!;
		case UNARY_EXPR:  n += f.printf("( %s %s )", self.as.u.op, self.as.u.right)!;
		case ASSIGN_EXPR: n += f.printf("( %s = %s )", self.as.a.op, self.as.a.right)!;
		case BINARY_EXPR: n += f.printf("( %s %s %s )", self.as.b.left, self.as.b.op, self.as.b.right)!;
		case CALL_EXPR:   n += f.printf("%s( %s )", self.as.c.func, self.as.c.args)!;
	}
	return n;
}

