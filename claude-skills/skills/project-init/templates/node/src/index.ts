export function greet(name: string): string {
  return `Hello, ${name}!`;
}

function main(): void {
  console.log(greet('world'));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
