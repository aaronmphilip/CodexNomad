package main

import (
	"fmt"
	"os"

	"github.com/codexnomad/codexnomad/daemon/internal/app"
)

func main() {
	if err := app.Run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "codexnomad: %v\n", err)
		os.Exit(1)
	}
}
