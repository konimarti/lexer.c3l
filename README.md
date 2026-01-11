# C3 Lexer

A lexical analyzer for the [C3 programming language](https://c3-lang.org/).
This project provides a complete lexer that can tokenize any valid C3 source
file, including the full standard library and all associated unit tests.

The **C3 Lexer** is designed to serve as a reliable foundation for language
tooling—parsers, formatters, and analyzers targeting the C3 ecosystem. It is
implemented in pure C3 and maintains close fidelity to the current grammar and
syntax rules of the language.

The lexer also supports language constructs such as **contract blocks** and
**inline documentation comments**.

## Features

- **Full lexical coverage:** Lexes the entire C3 standard library and all unit
  test files.

- **Comment and contract awareness:** Accurately processes all comment types
  and contract block definitions.

- **Dual-mode lexing:** A dedicated *contract lexer* is available to tokenize
  contract sections separately for improved modularity.

- **Zero allocations:** The lexer does not allocate any memory but instead
  returns tokens where the lexeme refers to the input string.

- **Robust testing:** Verified against the C3 standard library and all unit
  tests for complete lexical correctness.

## Notes

The lexer returns a token for line comments (`LINE_COMMENT`), block comments
(`BLOCK_COMMENT`), and contracts (`CONTRACT`).

If you want to step into the contracts and lex them too, then use the lexeme of
the `CONTRACT` token with the `ContractLexer`:

## Testing

The lexer is validated against:

- The complete C3 standard library
- All C3 compiler standard library unit tests

The lexer output is verified against the output of the C3 compiler (`c3c -E`).

## Example

```c3
import c3::lexer, std::io;
fn void main() => @pool()
{
	Lexer lexer;
	lexer.init((String)file::load_temp($$FILE)!!);
	while (try tok = lexer.next()) io::printn(tok);
}
```

## License

MIT License [konimarti](https://github.com/konimarti)
