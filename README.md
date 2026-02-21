# Python IDE for Android

A fully-featured, advanced Python IDE for Android built with Flutter. This app provides a complete Linux environment on Android, enabling the installation and execution of heavy Python modules including AI/ML libraries like PyTorch, TensorFlow, Transformers, and llama.cpp.

## Features

### Core IDE Features
- **Code Editor**: Syntax highlighting, auto-completion, line numbers, word wrap
- **File Explorer**: Project management with create, open, save, delete operations
- **Integrated Terminal**: Full bash access to the Linux environment
- **Output Console**: Real-time script execution output
- **Project Management**: Multiple project support with persistent storage

### Linux Environment
- **Complete Linux Distribution**: Alpine Linux or Ubuntu via proot
- **Python 3.10+**: Full Python installation with pip package management
- **Native Compilation**: Support for C/C++ extensions required by ML libraries
- **Isolated Environment**: Sandboxed Linux environment for safety

### AI/ML Support
- **PyTorch**: Run deep learning models
- **TensorFlow**: Machine learning workflows
- **Transformers**: Hugging Face model support
- **llama.cpp**: Local LLM inference with .gguf models
- **NumPy, Pandas, Matplotlib**: Data science essentials

### User Experience
- **Material Design 3**: Modern, responsive UI
- **Light/Dark Themes**: Automatic system theme detection
- **Offline Capable**: Work without internet after initial setup
- **Performance Optimized**: Lag-free editing and execution

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter UI Layer                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  Editor  │  │ Explorer │  │ Terminal │  │  Output  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                    Platform Channel
                            │
┌─────────────────────────────────────────────────────────────┐
│                  Android Native Layer                       │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              MainActivity (Kotlin)                  │   │
│  │  - Download & Extract Linux Rootfs                  │   │
│  │  - Process Management                               │   │
│  │  - File System Operations                           │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│                   Linux Environment                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  Python  │  │   pip    │  │  gcc/clang│  │  bash    │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ PyTorch  │  │TensorFlow│  │llama.cpp │  │  NumPy   │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
lib/
├── main.dart                    # App entry point
├── core/                        # Core utilities
├── models/                      # Data models
│   ├── project.dart
│   └── linux_environment.dart
├── providers/                   # State management
│   ├── theme_provider.dart
│   ├── linux_environment_provider.dart
│   ├── project_provider.dart
│   ├── editor_provider.dart
│   └── terminal_provider.dart
├── services/                    # Business logic
│   └── linux_environment_service.dart
├── screens/                     # UI screens
│   ├── splash_screen.dart
│   ├── setup_screen.dart
│   ├── main_screen.dart
│   ├── project_screen.dart
│   ├── settings_screen.dart
│   ├── package_manager_screen.dart
│   └── model_manager_screen.dart
└── widgets/                     # Reusable widgets
    ├── file_explorer.dart
    ├── code_editor.dart
    ├── terminal_panel.dart
    └── output_panel.dart

android/
└── app/
    └── src/
        └── main/
            └── kotlin/
                └── com/pythonide/
                    └── MainActivity.kt    # Platform channel implementation
```

## Setup Instructions

### Prerequisites
- Flutter SDK 3.0+
- Android SDK
- Kotlin 1.9+
- Android Studio or VS Code

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/python-ide-android.git
   cd python-ide-android
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Android**
   - Open `android/local.properties` and add:
     ```
     flutter.sdk=/path/to/flutter
     sdk.dir=/path/to/android/sdk
     ```

4. **Build the app**
   ```bash
   flutter build apk --release
   ```

5. **Install on device**
   ```bash
   flutter install
   ```

### First Run

1. Launch the app
2. Complete the setup wizard to download the Linux environment
3. Choose between Alpine Linux (smaller) or Ubuntu (full-featured)
4. Wait for the environment to download and install (~150-500MB)
5. Start coding!

## Usage Guide

### Creating a Project
1. Tap the "+" button in the Projects screen
2. Enter a project name
3. The app creates a project with a `main.py` file

### Writing Code
1. Select a file from the file explorer
2. Use the code editor with syntax highlighting
3. Press Ctrl+S (or use the save button) to save

### Running Code
1. Open a Python file
2. Tap the "Run" button (play icon)
3. View output in the Output panel

### Installing Packages
1. Navigate to the Packages tab
2. Search for a package or select from quick install
3. Tap install and wait for completion

### Using the Terminal
1. Open the Terminal panel
2. Type bash commands
3. Use `pip3` to manage packages
4. Use `python3` to run scripts

### Running LLM Models
1. Import a .gguf model file (from Hugging Face or other sources)
2. Go to the Models tab
3. Tap "Run" on your model
4. Enter prompts in the inference panel

## Supported Python Packages

### Data Science
- numpy, pandas, scipy
- matplotlib, seaborn, plotly
- scikit-learn

### Deep Learning
- torch, torchvision, torchaudio
- tensorflow, keras
- jax, flax

### NLP & LLMs
- transformers, tokenizers
- datasets, accelerate
- llama-cpp-python

### Web Development
- flask, django, fastapi
- requests, aiohttp
- sqlalchemy

### Utilities
- pillow, opencv-python
- pyyaml, toml
- pytest, black, flake8

## Technical Details

### Linux Environment
- **Base**: Alpine Linux 3.19 or Ubuntu 22.04
- **Container**: proot-based user-space chroot
- **Size**: ~150MB (Alpine) to ~500MB (Ubuntu)
- **Python**: 3.10+ with pip

### Performance Considerations
- Uses proot for non-root Linux environment
- Optimized for ARM64 (primary Android architecture)
- Background execution for long-running tasks
- Memory management for large models

### Security
- Sandboxed Linux environment
- No root access required
- Isolated file system
- Network permissions for package downloads only

## Troubleshooting

### Environment Not Installing
- Check internet connection
- Ensure sufficient storage space (1GB+)
- Try switching to a different distribution

### Package Installation Fails
- Some packages require compilation tools
- Install `build-base` (Alpine) or `build-essential` (Ubuntu)
- Check package compatibility with ARM architecture

### Out of Memory
- Close other apps
- Use smaller models (Q4_K_M quantization)
- Reduce batch sizes in ML scripts

### Slow Performance
- Use Alpine Linux for lighter footprint
- Close unused panels
- Enable word wrap for large files

## Development

### Adding New Features
1. Create provider in `lib/providers/`
2. Add UI in `lib/screens/` or `lib/widgets/`
3. Update platform channel in `MainActivity.kt` if needed

### Platform Channel Methods
- `downloadAndExtract`: Download and extract Linux rootfs
- `executeCommand`: Run commands in Linux environment
- `isEnvironmentReady`: Check environment status

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Flutter team for the amazing framework
- proot developers for the Linux environment solution
- llama.cpp project for local LLM inference
- Hugging Face for transformer models

## Support

For issues and feature requests, please use the GitHub issue tracker.

---

**Note**: This app requires Android 7.0+ (API level 24) and approximately 1GB of free storage for the Linux environment.
