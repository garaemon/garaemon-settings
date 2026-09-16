"""Entry point for __PROJECT_NAME__."""


def greet(name: str) -> str:
    """Return a friendly greeting for ``name``."""
    return f"Hello, {name}!"


def main() -> None:
    print(greet("world"))


if __name__ == "__main__":
    main()
