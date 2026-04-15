# CoreLM v1 — SwiftUI Screen Tree

## Navigation Architecture

CoreLM uses a **three-column layout** as its primary structure:

```
┌──────────┬───────────────────────────┬──────────────┐
│          │                           │              │
│ Sidebar  │      Main Content         │  Inspector   │
│          │                           │  (optional)  │
│          │                           │              │
│          │                           │              │
│          │                           │              │
│          │                           │              │
│          │                           │              │
│          │                           │              │
│          ├───────────────────────────┤              │
│          │  Bottom Panel (optional)  │              │
└──────────┴───────────────────────────┴──────────────┘
```

- **Sidebar**: 220pt fixed width, collapsible via toolbar button
- **Main Content**: flexible, minimum 500pt
- **Inspector**: 280pt fixed width, collapsible via toolbar button
- **Bottom Panel**: expandable/collapsible, 200pt default height

---

## Complete View Hierarchy

```
CoreLMApp (App)
└── WindowGroup
    └── ContentView
        ├── NavigationSplitView (three-column)
        │
        │── [Column 1] SidebarView
        │   ├── SidebarSection: "Chats"
        │   │   ├── NewChatButton
        │   │   └── ChatListView
        │   │       └── ChatRowView (for each chat)
        │   │           ├── Chat title
        │   │           ├── Last message preview
        │   │           ├── Timestamp
        │   │           └── Context menu (rename, delete)
        │   │
        │   ├── SidebarSection: "Models"
        │   │   └── NavigationLink → ModelListScreen
        │   │
        │   ├── SidebarSection: "Diagnostics"
        │   │   └── NavigationLink → DiagnosticsScreen
        │   │
        │   └── SidebarSection: "Settings"
        │       └── NavigationLink → SettingsScreen
        │
        │── [Column 2] MainContentView (detail)
        │   ├── ChatScreen (default)
        │   ├── ModelListScreen
        │   ├── DiagnosticsScreen
        │   ├── SettingsScreen
        │   └── WelcomeScreen (when no chat selected)
        │
        │── [Column 3] InspectorView (inspector)
        │   ├── ChatInspector (when in chat)
        │   ├── ModelInspector (when viewing model)
        │   └── RuntimeInspector (when in diagnostics)
        │
        └── [Bottom] BottomPanelView (overlay)
            └── RuntimeLogView
```

---

## Screen Specifications

### 1. WelcomeScreen

Shown when no chat is selected (app first launch or empty state).

```
┌─────────────────────────────────┐
│                                 │
│                                 │
│          CoreLM logo            │
│                                 │
│     "Start a new conversation"  │
│                                 │
│     [Select a Model ▼]          │
│     [New Chat]                  │
│                                 │
│    ── or ──                     │
│                                 │
│     [Import a Model]            │
│                                 │
│                                 │
└─────────────────────────────────┘
```

**Components:**
- `WelcomeScreen`
  - `ModelPickerDropdown` — shows loaded models, or prompts to import
  - `NewChatButton` — creates chat with selected model
  - `ImportModelButton` — opens file importer

---

### 2. ChatScreen

The primary interaction screen.

```
┌─────────────────────────────────┐
│ [Model: LLaMA 3.2 3B Q4_0]  ⚙ │  ← ChatHeaderBar
├─────────────────────────────────┤
│                                 │
│  ┌─────────────────────────┐    │
│  │ User                    │    │
│  │ Explain how attention   │    │
│  │ works in transformers.  │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │ Assistant               │    │
│  │ Attention is a mechanism│    │
│  │ that allows the model...│    │  ← MessageBubbleView
│  │ █                       │    │  ← streaming cursor
│  └─────────────────────────┘    │
│                                 │
├─────────────────────────────────┤
│ ┌─────────────────────────┐     │
│ │ Message...              │ [▶] │  ← PromptComposerView
│ └─────────────────────────┘     │
│ [Stop] [Regenerate] [Clear]     │  ← GenerationControlsView
└─────────────────────────────────┘
```

**Components:**
- `ChatScreen`
  - `ChatHeaderBar`
    - Model name + quantization badge
    - Settings gear (opens generation params in inspector)
  - `MessageListView` (ScrollView, lazy)
    - `MessageBubbleView` (for each message)
      - Role indicator (User / Assistant)
      - `MarkdownContentView` — renders markdown with code blocks
      - Copy button (on hover)
      - Timestamp (on hover)
  - `PromptComposerView`
    - Multi-line text editor
    - Send button (or Enter)
    - Character/token estimate
  - `GenerationControlsView`
    - Stop button (visible during generation)
    - Regenerate button (visible after generation)
    - Clear context button

**State Machine:**
```
Idle → Composing → Generating → Streaming → Complete
                                    ↓
                               Cancelled
```

---

### 3. ModelListScreen

```
┌─────────────────────────────────┐
│ Models                 [Import] │
├─────────────────────────────────┤
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ● LLaMA 3.2 3B             │ │  ← ModelCardView (loaded)
│ │   Q4_0 · 1.8 GB · Loaded   │ │
│ │   [Unload]                  │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ○ Mistral 7B                │ │  ← ModelCardView (available)
│ │   Q4_K_M · 4.1 GB          │ │
│ │   [Load]                    │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ○ LLaMA 3.1 8B             │ │
│ │   Q4_0 · 4.5 GB            │ │
│ │   [Load]                    │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

**Components:**
- `ModelListScreen`
  - `ModelListHeaderView`
    - Title
    - Import button (opens file picker for .gguf files)
  - `ModelCardView` (for each registered model)
    - Model name
    - Architecture badge
    - Quantization badge
    - File size
    - Status indicator (loaded / available / error)
    - Load / Unload action button
    - Context menu (show in Finder, remove from registry, view details)

**Model Import Flow:**
```
[Import button] → File picker (.gguf filter)
                      │
                      ▼
              Validate GGUF header
                      │
                 ┌────┴────┐
                 │         │
              Valid     Invalid
                 │         │
                 ▼         ▼
           Add to      Show error
           registry    alert
                 │
                 ▼
           Show in list
           (not loaded)
```

---

### 4. DiagnosticsScreen

```
┌─────────────────────────────────┐
│ Diagnostics                     │
├─────────────────────────────────┤
│                                 │
│ Runtime Status                  │
│ ┌──────────┬──────────────────┐ │
│ │ Backend  │ CPU (Accelerate) │ │
│ │ State    │ Ready            │ │
│ │ Model    │ LLaMA 3.2 3B    │ │
│ └──────────┴──────────────────┘ │
│                                 │
│ Performance                     │
│ ┌──────────┬──────────────────┐ │
│ │ Load     │ 1.23s            │ │
│ │ Prompt   │ 142.5 tok/s      │ │
│ │ Generate │ 38.2 tok/s       │ │
│ │ 1st Token│ 87ms             │ │
│ └──────────┴──────────────────┘ │
│                                 │
│ Memory                          │
│ ┌──────────┬──────────────────┐ │
│ │ Model    │ 1.8 GB           │ │
│ │ KV Cache │ 256 MB           │ │
│ │ Scratch  │ 48 MB            │ │
│ │ Total    │ 2.1 GB           │ │
│ └──────────┴──────────────────┘ │
│                                 │
│ Context                         │
│ ┌──────────┬──────────────────┐ │
│ │ Tokens   │ 1,247 / 4,096   │ │
│ │ Cache    │ 78% utilized     │ │
│ └──────────┴──────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

**Components:**
- `DiagnosticsScreen`
  - `RuntimeStatusSection`
    - Backend name
    - Runtime state
    - Loaded model info
  - `PerformanceSection`
    - Model load duration
    - Prompt evaluation speed (tok/s)
    - Generation speed (tok/s)
    - Time to first token
    - Total generation time
  - `MemorySection`
    - Model memory footprint
    - KV cache allocation
    - Scratch buffer usage
    - Total estimated usage
  - `ContextSection`
    - Current token count / max context
    - Cache utilization percentage

All values update in real-time during generation via `@Observable` bindings.

---

### 5. SettingsScreen

```
┌─────────────────────────────────┐
│ Settings                        │
├─────────────────────────────────┤
│                                 │
│ Generation                      │
│ ┌─────────────────────────────┐ │
│ │ Temperature      [0.7    ] │ │
│ │ Top-K            [40     ] │ │
│ │ Top-P            [0.95   ] │ │
│ │ Max Tokens       [2048   ] │ │
│ │ Repeat Penalty   [1.1    ] │ │
│ │ Seed             [auto   ] │ │
│ └─────────────────────────────┘ │
│                                 │
│ Runtime                         │
│ ┌─────────────────────────────┐ │
│ │ Backend       [Auto ▼]     │ │
│ │ Context Size  [4096 ▼]     │ │
│ │ Batch Size    [512  ▼]     │ │
│ └─────────────────────────────┘ │
│                                 │
│ Appearance                      │
│ ┌─────────────────────────────┐ │
│ │ Theme         [System ▼]   │ │
│ │ Font Size     [14px ▼]     │ │
│ └─────────────────────────────┘ │
│                                 │
│ Developer                       │
│ ┌─────────────────────────────┐ │
│ │ Developer Mode  [Toggle]   │ │
│ │ Verbose Logging [Toggle]   │ │
│ │ Show Debug Panel[Toggle]   │ │
│ │ Model Directory [Browse]   │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

**Components:**
- `SettingsScreen`
  - `GenerationSettingsSection`
    - Temperature slider + text field
    - Top-K stepper
    - Top-P slider
    - Max tokens stepper
    - Repetition penalty slider
    - Seed field (auto or fixed integer)
  - `RuntimeSettingsSection`
    - Backend picker (Auto / CPU / Metal)
    - Context size picker
    - Batch size picker
  - `AppearanceSettingsSection`
    - Theme picker (System / Dark / Light)
    - Font size picker
  - `DeveloperSettingsSection`
    - Developer mode toggle
    - Verbose logging toggle
    - Debug panel toggle
    - Model directory path picker

---

### 6. Inspector Panels

#### ChatInspector

Shown when a chat is active. Displays contextual information.

```
┌──────────────────┐
│ Session           │
│ Model: LLaMA 3.2 │
│ Backend: CPU      │
│ Context: 847/4096 │
│                   │
│ Generation        │
│ Temp: 0.7         │
│ Top-K: 40         │
│ Top-P: 0.95       │
│                   │
│ Last Run          │
│ Tokens: 234       │
│ Speed: 38 tok/s   │
│ Duration: 6.2s    │
│                   │
│ Memory            │
│ Model: 1.8 GB     │
│ Cache: 256 MB     │
└──────────────────┘
```

#### ModelInspector

Shown when viewing model details.

```
┌──────────────────┐
│ LLaMA 3.2 3B     │
│                   │
│ Architecture      │
│ Type: llama       │
│ Params: 3.21B     │
│ Layers: 28        │
│ Heads: 24         │
│ KV Heads: 8       │
│ Hidden: 3072      │
│ Context: 8192     │
│                   │
│ Quantization      │
│ Type: Q4_0        │
│ File: 1.8 GB      │
│                   │
│ Tokenizer         │
│ Type: BPE         │
│ Vocab: 128,256    │
│                   │
│ File              │
│ Path: /Models/... │
│ Modified: Apr 12  │
└──────────────────┘
```

---

### 7. Bottom Runtime Panel

Expandable log/debug panel anchored to the bottom of the main content area.

```
┌─────────────────────────────────────────────┐
│ Runtime Log                        [▼ Hide] │
├─────────────────────────────────────────────┤
│ 14:23:01.234  INFO   Model loaded (1.23s)   │
│ 14:23:05.891  INFO   Session created         │
│ 14:23:06.012  DEBUG  Prompt eval: 12 tokens  │
│ 14:23:06.096  DEBUG  Prompt eval: 142 tok/s  │
│ 14:23:06.098  INFO   Generation started       │
│ 14:23:12.341  INFO   Generation complete      │
│ 14:23:12.342  DEBUG  234 tokens, 38.2 tok/s  │
│ 14:23:12.342  DEBUG  KV cache: 847/4096      │
└─────────────────────────────────────────────┘
```

**Components:**
- `BottomPanelView`
  - Drag handle for resizing
  - `RuntimeLogView`
    - Scrollable log entries
    - Log level color coding
    - Timestamp display
    - Auto-scroll toggle
    - Clear button
    - Filter by level

---

## View Model Architecture

```
ChatScreen ◄──── ChatViewModel
                      │
                      ├── chatStore: ChatStore (persistence)
                      ├── runtime: CoreLMRuntime (bridge)
                      └── currentSession: InferenceSession?

ModelListScreen ◄── ModelListViewModel
                          │
                          ├── registry: ModelRegistry (persistence)
                          └── runtime: CoreLMRuntime (bridge)

DiagnosticsScreen ◄── DiagnosticsViewModel
                             │
                             └── runtime: CoreLMRuntime (metrics)

SettingsScreen ◄── SettingsViewModel
                         │
                         └── settingsStore: SettingsStore
```

---

## Keyboard Shortcuts (v1)

| Shortcut | Action |
|----------|--------|
| ⌘N | New chat |
| ⌘⏎ | Send message |
| ⌘. | Stop generation |
| ⌘⇧R | Regenerate last |
| ⌘⇧⌫ | Clear context |
| ⌘1 | Show Chats sidebar |
| ⌘2 | Show Models |
| ⌘3 | Show Diagnostics |
| ⌘, | Settings |
| ⌘⌥I | Toggle inspector |
| ⌘⇧D | Toggle debug panel |

---

## Window Configuration

- **Minimum size:** 900 × 600
- **Default size:** 1200 × 800
- **Title bar:** Unified toolbar style (`.windowToolbarStyle(.unified)`)
- **Sidebar:** NavigationSplitView with `.sidebar` column visibility
- **Multiple windows:** Not supported in v1 (single window app)
