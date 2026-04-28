package main

import (
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
)

func freezeSharingd(name string, freeze bool) (bool, error) {
	action := "-CONT"
	if freeze {
		action = "-STOP"
	}

	cmd := exec.Command("killall", action, name)
	err := cmd.Run()

	if err != nil {
		return false, err
	}
	return freeze, nil
}

func interfaces(intf string, state string) error {
	cmd := exec.Command("ifconfig", intf, state)
	err := cmd.Run()
	if err != nil {
		return fmt.Errorf("failed to trigger state %s on interface:%s: %w", intf, state, err)
	}
	fmt.Println(intf, "->", state)
	return nil
}

func on() {
	_, err := freezeSharingd("sharingd", true)
	if err != nil {
		fmt.Println("Could not stop the daemon, is it already stoped?):", err)
	}
	errAwdl := interfaces("awdl0", "down")
	if errAwdl != nil {
		fmt.Println(errAwdl)
		os.Exit(1)
	}
	errLlw := interfaces("llw0", "down")
	if errLlw != nil {
		fmt.Println(errLlw)
		os.Exit(1)
	}
}
func off() {
	errAwdl := interfaces("awdl0", "up")
	if errAwdl != nil {
		fmt.Println(errAwdl)
	}

	errLlw := interfaces("llw0", "up")
	if errLlw != nil {
		fmt.Println(errLlw)
	}

	_, err := freezeSharingd("sharingd", false)
	if err != nil {
		fmt.Println(err)
	}
}

func interactive() {
	on()
	fmt.Println("Both interfaces down. Program running... press ctrl+c to exit when you are done")
	canal := make(chan os.Signal, 1)
	signal.Notify(canal, os.Interrupt, syscall.SIGTERM)
	<-canal
	fmt.Println("")
	fmt.Println("Closing the program...")
	off()

}

func main() {
	if os.Geteuid() != 0 {
		fmt.Println("Need sudo to execute")
		os.Exit(1)
	}
	if len(os.Args) == 1 {
		interactive()
		return
	}
	flag := os.Args[1]

	switch flag {
	case "on":
		on()
	case "off":
		off()
	default:
		fmt.Println("valid arguments: --on,--off")
	}
}
