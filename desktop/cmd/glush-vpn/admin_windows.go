//go:build windows
// +build windows

package main

import (
	"golang.org/x/sys/windows"
)

// isAdmin checks if the process has admin privileges (required for WireGuard on Windows).
func isAdmin() bool {
	_, err := windows.OpenCurrentProcessToken()
	if err != nil {
		return false
	}
	var sid *windows.SID
	err = windows.AllocateAndInitializeSid(
		&windows.SECURITY_NT_AUTHORITY,
		2,
		windows.SECURITY_BUILTIN_DOMAIN_RID,
		windows.DOMAIN_ALIAS_RID_ADMINS,
		0, 0, 0, 0, 0, 0,
		&sid,
	)
	if err != nil {
		return false
	}
	defer windows.FreeSid(sid)
	token, err := windows.OpenCurrentProcessToken()
	if err != nil {
		return false
	}
	defer token.Close()
	member, err := token.IsMember(sid)
	return err == nil && member
}
