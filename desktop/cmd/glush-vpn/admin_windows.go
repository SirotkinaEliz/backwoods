//go:build windows
// +build windows

package main

import (
	"os"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

// isAdmin checks if the process has admin privileges (required for WireGuard on Windows).
func isAdmin() bool {
	var sid *windows.SID
	err := windows.AllocateAndInitializeSid(
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

// ensureAdmin проверяет права и, если их нет, перезапускает приложение через UAC.
// Если пользователь отклонил UAC — показывает MessageBox и завершается.
func ensureAdmin() {
	if isAdmin() {
		return
	}
	// Попытка перезапустить с elevation через ShellExecuteW "runas"
	if relaunchAsAdmin() {
		os.Exit(0) // текущий процесс завершается, запущен новый с UAC
	}
	// Пользователь отклонил UAC или ошибка — показываем MessageBox
	showMessageBox(
		"GLUSH VPN",
		"Приложению требуются права администратора.\n\n"+
			"Нажмите правой кнопкой на файл GLUSH-VPN.exe\nи выберите \"Запустить от имени администратора\".",
		0x10, // MB_ICONERROR
	)
	os.Exit(1)
}

// relaunchAsAdmin перезапускает текущий EXE через ShellExecuteW с глаголом "runas" (UAC).
func relaunchAsAdmin() bool {
	exePath, err := os.Executable()
	if err != nil {
		return false
	}
	shell32 := syscall.NewLazyDLL("shell32.dll")
	shellExecuteW := shell32.NewProc("ShellExecuteW")
	verb, _ := syscall.UTF16PtrFromString("runas")
	path, _ := syscall.UTF16PtrFromString(exePath)
	ret, _, _ := shellExecuteW.Call(
		0,
		uintptr(unsafe.Pointer(verb)),
		uintptr(unsafe.Pointer(path)),
		0, 0,
		uintptr(syscall.SW_SHOWNORMAL),
	)
	return int32(ret) > 32
}

// showMessageBox показывает диалог Windows MessageBox.
func showMessageBox(title, text string, uType uint32) {
	user32 := syscall.NewLazyDLL("user32.dll")
	msgBox := user32.NewProc("MessageBoxW")
	t, _ := syscall.UTF16PtrFromString(title)
	m, _ := syscall.UTF16PtrFromString(text)
	msgBox.Call(0, uintptr(unsafe.Pointer(m)), uintptr(unsafe.Pointer(t)), uintptr(uType))
}
