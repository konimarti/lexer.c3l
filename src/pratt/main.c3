module pratt;

import std::io;
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
		if (parselet.infix == null || min_bp >= parselet.bp) break;

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

struct Parselet
{
	PrefixParselet prefix;
	InfixParselet  infix;
	int            bp;
	Assoc          assoc;
}

Parselet[*] pratt_table = {
	[TokenType.STRING..TokenType.HASH_CONST_IDENT] = { &parse_ident,  null, 0, Assoc.NONE },
	[TokenType.INTEGER] = { &parse_number, null,           0, Assoc.NONE },
	[TokenType.REAL]    = { &parse_number, null,           0, Assoc.NONE },
	[TokenType.PLUS]    = { null,          &parse_binary, 10, Assoc.LEFT },
	[TokenType.STAR]    = { null,          &parse_binary, 20, Assoc.LEFT },
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

fn Expr*? parse_binary(PrattParser *p, Expr *left, Token tok)
{
	Parselet parselet = pratt_table[tok.type];
	int next_bp = parselet.bp + parselet.assoc; // If left assoc, add 1 to bp.

	Expr* right = parse_expr(p, next_bp)!;

	Expr *e = mem::tnew(Expr);
	*e = { .kind = BINARY_EXPR, .as.b = { tok, left, right} };

	return e;
}


/*
 Expressions
*/

alias NumberExpression = Token;
alias IdentExpression = Token;

struct BinaryExpression
{
	Token op;
	Expr *left;
	Expr *right;
}

enum ExprKind
{
	NUMBER_EXPR,
	IDENT_EXPR,
	BINARY_EXPR
}

struct Expr (Printable)
{
	ExprKind kind;
	union as {
		NumberExpression n;
		IdentExpression  i;
		BinaryExpression b;
	}
}

fn usz? Expr.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	switch (self.kind)
	{
		case NUMBER_EXPR: n += f.printf("%s", self.as.n)!;
		case IDENT_EXPR:  n += f.printf("%s", self.as.i)!;
		case BINARY_EXPR: n += f.printf("( %s %s %s )", self.as.b.left, self.as.b.op, self.as.b.right)!;
	}
	return n;
}

