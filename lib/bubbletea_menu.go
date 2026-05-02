package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
)

type model struct {
	cursor  int
	choices []string
	keys    []string
	quitting bool
}

func initialModel() model {
	return model{
		choices: []string{
			"System-Python + venv [EMPFOHLEN]",
			"Python 3.9.25 kompilieren [ORIGINAL]",
			"Python 3.14.4 + venv [NEUESTE]",
			"Feature-Patches verwalten",
			"Legacy Wallbox Module",
			"Tools installieren",
			"Status anzeigen",
			"Diagnose-Archiv erstellen",
			"Diagnose anonymisieren + hochladen",
			"Beenden",
		},
		keys: []string{"venv", "python39", "python314", "patches", "legacy_wallbox", "tools", "status", "diagnose", "diagnose_upload", "quit"},
	}
}

func (m model) Init() tea.Cmd { return nil }

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			m.quitting = true
			return m, tea.Quit
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.choices)-1 {
				m.cursor++
			}
		case "enter":
			fmt.Println(m.keys[m.cursor])
			m.quitting = true
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m model) View() string {
	if m.quitting {
		return ""
	}
	s := "OpenWB Installer (Bubble Tea)\n\n"
	for i, c := range m.choices {
		cursor := " "
		if m.cursor == i {
			cursor = ">"
		}
		s += fmt.Sprintf("%s %s\n", cursor, c)
	}
	s += "\n↑/↓ wählen, Enter bestätigen, q abbrechen.\n"
	return s
}

func main() {
	p := tea.NewProgram(initialModel())
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
