package main

import "testing"

func TestGreet(t *testing.T) {
	got := Greet("world")
	want := "Hello, world!"
	if got != want {
		t.Errorf("Greet(\"world\") = %q, want %q", got, want)
	}
}
