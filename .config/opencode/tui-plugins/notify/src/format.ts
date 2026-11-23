const ESC = "\x1b"

export function clean(text: string | undefined, max: number): string {
  return (text ?? "")
    .replace(/[;\r\n]+/g, " ")
    .replace(/[\u0000-\u001f\u007f-\u009f]/g, "")
    .trim()
    .slice(0, max)
}

// OSC 777 is shown as a toast by WezTerm.
export function sequence(title: string, body: string): string {
  return `${ESC}]777;notify;${title};${body}${ESC}\\`
}

// `tmux list-clients -F '#{client_activity} #{client_tty}'` → most recently active client's tty.
export function client(list: string): string | undefined {
  return list
    .split("\n")
    .map((line) => line.trim().split(" "))
    .filter(([activity, tty]) => activity && tty)
    .sort(([a], [b]) => Number(b) - Number(a))[0]?.[1]
}

// Every TUI receives events for all sessions on the server; notify only for the ones this TUI shows.
export function shown(id: string, tabs: string[] | undefined, route: string | undefined): boolean {
  return tabs ? tabs.includes(id) : route === id
}
