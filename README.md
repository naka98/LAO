# LAO macOS App

LAO is a macOS-native AI design workflow application built with SwiftUI. It transforms ideas into AI-execution-friendly design documents through CLI-based AI agents.

---

## Features

### Design Workflow (Primary Feature)
- AI-powered design structuring: idea exploration, approach selection, deliverable elaboration
- Multi-phase execution: Input → Analyzing → Approach Selection → Planning → Completed
- Human-in-the-loop decisions at key checkpoints
- Background execution with notification system
- Design session persistence and resume capability

### IdeaBoard (Main Hub)
- Idea exploration with AI expert panels
- Direction synthesis and Work Graph extraction
- Seamless transition from idea to design workflow

### Project Management
- Multi-project workspace with launcher
- Agent configuration (Director, Fallback, Step tiers)
- Provider support: Claude, Codex, Gemini
- Skill management per project

---

## Architecture

### Directory Structure

```
LAO/
├── project.yml                        # XcodeGen spec
├── Package.swift                      # SPM package definition
├── LAOApp/                            # SwiftUI application
│   ├── App/
│   │   ├── LAOApp.swift               # @main entry point (multi-window Scene API)
│   │   ├── AppContainer.swift         # DI container
│   │   ├── LAOAppDelegate.swift       # App delegate
│   │   ├── DesignDocumentWindowCoordinator.swift  # Design doc window lifecycle
│   │   ├── ProjectWindowRoute.swift   # Window routing
│   │   ├── LAOWindowLayoutMode.swift  # Window sizing
│   │   └── DemoSeedMode.swift         # Demo/seed data
│   ├── Features/
│   │   ├── Design/                    # Design workflow (main feature)
│   │   │   ├── DesignModels.swift             # Data models, enums
│   │   │   ├── DesignPromptBuilder.swift      # LLM prompt templates
│   │   │   ├── DesignWorkflowViewModel.swift  # State management, execution engine
│   │   │   ├── DesignWorkflowView.swift       # Main UI (phase-based screens)
│   │   │   ├── ActiveWorkflowCoordinator.swift # Background lifecycle, project queue
│   │   │   └── ...                            # Overlays, converters, validators
│   │   ├── IdeaBoard/                 # Idea management hub
│   │   │   ├── IdeaBoardView.swift
│   │   │   ├── IdeaDetailView.swift
│   │   │   ├── IdeaPromptBuilder.swift
│   │   │   └── IdeaBoardModels.swift
│   │   ├── Launcher/                  # Project launcher & workspace
│   │   ├── ProjectDashboard/          # Project settings (General, Agents, Skills)
│   │   └── SharedUI/                  # Theme, components, button styles
│   └── ViewModels/                    # Shared ViewModels
├── Packages/
│   ├── LAODomain/       # Domain models, enums, protocols
│   ├── LAOServices/     # Service protocol definitions
│   ├── LAOPersistence/  # SQLite CRUD, schema bootstrap
│   ├── LAORuntime/      # CLI agent execution, git, model catalog
│   ├── LAOProviders/    # Provider registry and support
│   └── LAOMCPServer/    # MCP server executable
```

### Key Patterns

- **Multi-window architecture**: Scene API-based windows (Launcher, ProjectWorkspace, Settings, DesignDocument)
- **ActiveWorkflowCoordinator**: Singleton managing background design execution, project-level queuing, and ViewModel lifecycle
- **DesignPromptBuilder**: Centralized prompt construction for all LLM interactions
- **AppContainer**: Dependency injection container holding all services

---

## Build & Run

### Prerequisites
- macOS 15.0+ (Sequoia)
- Xcode 16.0+
- XcodeGen (`brew install xcodegen`)

### Setup
1. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```
2. Open `LAO.xcodeproj` in Xcode
3. Select the `LAO` scheme and run

### CLI Build
```bash
xcodebuild -project LAO.xcodeproj -scheme LAO -destination 'platform=macOS' build
```

### AI Provider Setup
Configure at least one CLI agent provider in Settings → Agents:
- **Claude**: `claude` CLI must be available in PATH
- **Codex**: `codex` CLI must be available in PATH
- **Gemini**: `gemini` CLI must be available in PATH

---

## Data Storage

- SQLite database at `~/Library/Application Support/LAO/`
- Design documents saved per-request at `{project_root}/.lao/docs/{request_id}/`

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
