package main

import "fmt"

// Greet returns a friendly greeting for name.
func Greet(name string) string {
	return fmt.Sprintf("Hello, %s!", name)
}

func main() {
	fmt.Println(Greet("world"))
}
