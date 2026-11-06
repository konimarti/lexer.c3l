module c3::lexer::tests;

import c3::lexer @public;

<*
 Lex `input` and return its tokens (temp-allocated).
*>
fn Token[] lex_all(String input) @private
{
	Token[] out = mem::temp_array(Token, input.len + 1);
	sz n = 0;
	Lexer lex;
	lex.init(input);
	while (try tok = lex.next()) out[n++] = tok;
	assert(lex.at_end(), "the lexer must reach the end of the input");
	return out[:n];
}

fn void test_contract_lexer() @test
{
	ContractLexer dl;
	dl.init(`<*
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
	};

	while (try tok = dl.next() && want.len)
	{
		assert(tok.type == want[0], "Token type mismatch: got=%s, but want=%s", tok.type, want[0]);
		want = want[1..];
	}
	assert(dl.intro.trim() == "Check if a character is in a set.");
}

fn void test_number_then_member_access() @test
{
	String[3] srcs = { "90.0.to_radians()", "1e5.foo", "0x1p3.foo" };
	foreach (src : srcs)
	{
		Token[] toks = lex_all(src);
		assert(toks[0].type == REAL, "%s: got %s", src, toks[0].type);
		assert(toks[1].type == DOT && toks[2].type == IDENT, "%s: member access is lexed on its own", src);
	}
}

fn void test_unterminated_string_stops_at_line_end() @test
{
	Token[] toks = lex_all("a = \"abc;\nint x;");
	assert(toks[2].type == STRING && toks[2].unterminated);
	assert(toks[2].text == "\"abc;", "got %s", toks[2].text);
	assert(toks[3].type == INT && toks[3].ln == 2 && toks[3].col == 1, "the next line lexes normally");
}

fn void test_unterminated_literals_at_eof_are_tokens() @test
{
	foreach (src : (String[]){ "\"abc", "'a", "`abc", "\"abc\\", "x\"00", "/* x", "<* x" })
	{
		Token[] toks = lex_all(src);
		assert(toks.len == 1 && toks[0].unterminated && toks[0].text == src, "for %s", src);
	}
}

fn void test_closed_literals_are_terminated() @test
{
	foreach (src : (String[]){ "\"a\\\"b\"", "'a'", "`a``b`", "x\"00\n11\"", "/* /* */ */", "<* x *>" })
	{
		Token[] toks = lex_all(src);
		assert(toks.len == 1 && !toks[0].unterminated && toks[0].text == src, "for %s", src);
	}
}

fn void test_escape_never_takes_the_newline() @test
{
	Token[] toks = lex_all("\"a\\\nb\"");
	assert(toks[0].type == STRING && toks[0].unterminated && toks[0].text == "\"a\\");
}

fn void test_invalid_utf8_char_is_one_token() @test
{
	Token[] toks = lex_all("x = \xe2\x80\x9cy;");
	assert(toks[2].type == INVALID && toks[2].len == 3);
	assert(toks[3].type == IDENT && toks[3].text == "y");
}

fn void test_hex_e_is_not_an_exponent() @test
{
	Token[] toks = lex_all("0xFE-1 1e-5");
	assert(toks.len == 4, "got %d tokens", toks.len);
	assert(toks[0].type == INTEGER && toks[1].type == MINUS && toks[2].type == INTEGER);
	assert(toks[3].type == REAL && toks[3].text == "1e-5");
}

fn void test_compile_time_keywords_08() @test
{
	Token[] toks = lex_all("$Typeof $Typefrom $feat $feature $reflect $embed $expand $typeof $sizeof");
	TokenType[] want = { CT_TYPEOF, CT_TYPEFROM, CT_FEAT, CT_FEATURE, CT_REFLECT, CT_EMBED, CT_EXPAND, CT_IDENT, CT_IDENT };
	foreach (i, t : want) assert(toks[i].type == t, "token %d: got %s", i, toks[i].type);
}

fn void test_type_keywords_08() @test
{
	Token[] toks = lex_all("bfloat untypedlist bfloat16 isz sz attrmacro");
	TokenType[] want = { BFLOAT, UNTYPEDLIST, IDENT, IDENT, ISZ, ATTRMACRO };
	foreach (i, t : want) assert(toks[i].type == t, "token %d: got %s", i, toks[i].type);
}

fn void test_bare_at_and_hash() @test
{
	Token[] toks = lex_all("@ # @foo #bar");
	TokenType[] want = { AT, HASH, AT_IDENT, HASH_IDENT };
	foreach (i, t : want) assert(toks[i].type == t, "token %d: got %s", i, toks[i].type);
}

fn void test_underscore_and_hash_at_prefixes() @test
{
	// Mirrors the compiler: a lone '_' is UNDERSCORE, `#` only prefixes an ident
	// before a lowercase letter, `@` before a letter or '_'.
	Token[] toks = lex_all("_ _a #_ #Foo #FOO #_foo @1 #1");
	TokenType[] want = {
		UNDERSCORE, IDENT, HASH, UNDERSCORE, HASH, TYPE_IDENT, HASH, CONST_IDENT,
		HASH_IDENT, AT, INTEGER, HASH, INTEGER,
	};
	foreach (i, t : want) assert(toks[i].type == t, "token %d: got %s", i, toks[i].type);
}

fn void test_shebang_only_on_first_line() @test
{
	assert(lex_all("#!/usr/bin/env c3\nx")[0].type == LINE_COMMENT);
	Token[] toks = lex_all("a #!b");
	assert(toks[1].type == HASH && toks[2].type == BANG);
}

fn void test_token_position_is_its_start() @test
{
	Token[] toks = lex_all("a\n  /* x\n y */ b");
	assert(toks[1].ln == 2 && toks[1].col == 3, "comment starts at 2:3, got %d:%d", toks[1].ln, toks[1].col);
	assert(toks[1].nl_before == 1);
	assert(toks[2].ln == 3 && toks[2].nl_before == 0, "newlines inside the comment are not before `b`");
}

fn void test_number_classify() @test
{
	assert(number::classify("+")          ==  INVALID);
	assert(number::classify("-")          ==  INVALID);
	assert(number::classify("0")          ==  INTEGER);
	assert(number::classify("-1")         ==  INTEGER);
	assert(number::classify("123")        ==  INTEGER);
	assert(number::classify("123ul")      ==  INTEGER);
	assert(number::classify("123i32")     ==  INVALID);
	assert(number::classify("0xdeadbeeF") ==  INTEGER);
	assert(number::classify("0xcafeUL")   ==  INTEGER);
	assert(number::classify("0b101UL")    ==  INTEGER);
	assert(number::classify("1xbeef")     ==  INVALID);
	assert(number::classify("0b1001.001") ==  INVALID);
	assert(number::classify("0b123")      ==  INVALID);
	assert(number::classify("0xbeeF.123p1") == REAL);
	assert(number::classify("0f")         ==   REAL);
	assert(number::classify("0.5f")       ==   REAL);
	assert(number::classify("123.0")      ==   REAL);
	assert(number::classify("123.0e-10")  ==   REAL);
	assert(number::classify("123f")       ==   REAL);
	assert(number::classify("123d")       ==   REAL);
	assert(number::classify("1.0F")       ==   REAL);
	assert(number::classify("2D")         ==   REAL);
	assert(number::classify("1.")         ==   REAL);
	assert(number::classify("1.e5")       ==   REAL);
	assert(number::classify("1_.5")       ==   REAL);
	assert(number::classify("0x1.p1")     ==   REAL);
	assert(number::classify("1uLL")       ==   INTEGER);
	assert(number::classify("1Ll")        ==   INTEGER);
	assert(number::classify("1_000")      ==   INTEGER);
	assert(number::classify("0x1_F")      ==   INTEGER);
	assert(number::classify("1lu")        ==   INVALID);
	assert(number::classify("1u8")        ==   INVALID);
	assert(number::classify("1__2")       ==   INVALID);
	assert(number::classify("1_")         ==   INVALID);
	assert(number::classify("0x")         ==   INVALID);
	assert(number::classify("0x_1")       ==   INVALID);
	assert(number::classify("0b_1")       ==   INVALID);
	assert(number::classify("1._5")       ==   INVALID);
	assert(number::classify("1e1_0")      ==   INVALID);
	assert(number::classify("1.0u")       ==   INVALID);
	assert(number::classify("1e")         ==   INVALID);
	assert(number::classify("0x1p")       ==   INVALID);
}

fn void test_ident_classify() @test
{
	assert(ident::classify("AABB") == CONST_IDENT);
	assert(ident::classify("Aabb") == TYPE_IDENT);
	assert(ident::classify("aabb") == IDENT);
	assert(ident::classify("aaBb") == IDENT);
	assert(ident::classify("@AABB") == AT_CONST_IDENT);
	assert(ident::classify("@Aabb") == AT_TYPE_IDENT);
	assert(ident::classify("@aabb") == AT_IDENT);
	assert(ident::classify("#aabb") == HASH_IDENT);
	assert(ident::classify("$AABB") == CT_CONST_IDENT);
	assert(ident::classify("$Aabb") == CT_TYPE_IDENT);
	assert(ident::classify("$aabb") == CT_IDENT);
	assert(ident::classify("_") == UNDERSCORE);
	assert(ident::classify("__") == INVALID);
	assert(ident::classify("_a") == IDENT);
}
