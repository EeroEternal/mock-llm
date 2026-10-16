# Repository Rules for Agents (`AGENTS.md`)

## 1. Language Policy (Strict English-Only)

- **All repository documentation (`README.md`, `docs/**/*.md`), code comments, commit messages, PR descriptions, and CLI/log strings MUST be written strictly in English.**
- **Do NOT create Chinese or bilingual documentation files.**

## 2. Verification Gates

- Before finishing any change, run:
  ```bash
  cargo fmt --check
  cargo clippy --all-targets -- -D warnings
  cargo test
  ```
