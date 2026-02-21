
# Pyom App Blueprint

## Overview

Pyom is a Flutter-based mobile and desktop application that provides a Python IDE in a simulated Linux environment. It enables users to write, execute, and manage Python projects with package management support.

## Features

*   **Python IDE:** A feature-rich code editor with syntax highlighting, line numbers, and undo/redo functionality.
*   **Linux Environment:** A simulated Linux environment using `proot` to run Python code and `pip` for package management.
*   **Project Management:** Users can create, open, rename, and delete multiple Python projects.
*   **File Management:** Users can create, open, save, and delete files within a project.
*   **Package Management:** A dedicated screen to install and manage Python packages using `pip`.
*   **Model Management:** A dedicated screen to manage machine learning models.
*   **Responsive UI:** The application adapts to both mobile and desktop screen sizes, providing an optimized layout for each.
*   **Persistent State:** The app saves editor settings and the last opened project and file, ensuring a seamless experience across sessions.

## Design and Style

*   **Theme:** The app uses a modern theme with `flex_color_scheme` and supports Material You dynamic color.
*   **Layout:** The app features a responsive layout with a navigation rail for desktop and a drawer for mobile.
*   **UI Components:** The app utilizes a range of Material Design components, including a code editor, file explorer, terminal, and output panel.

## Current Change: Bug Fixes and Stability Improvements

This update addresses several critical bugs to improve the stability and usability of the application.

### Steps Taken

1.  **Bug #1 — App Resets to Setup Screen on Every Launch (Fixed):**
    *   Modified `lib/screens/splash_screen.dart` to correctly check the initialization status of the Linux environment.

2.  **Bug #2 — UI Overflow on Smaller Screens (Fixed):**
    *   Implemented a `LayoutBuilder` in `lib/screens/main_screen.dart` to provide a responsive UI for both mobile and desktop layouts.

3.  **Bug #3 — File Tabs Not Showing (Fixed):**
    *   Corrected the logic in `lib/providers/project_provider.dart` to properly set the `isOpen` flag when a file is opened.

4.  **Bug #4 — Editor Not Updating When Switching Files (Fixed):**
    *   Added a listener in `lib/widgets/code_editor.dart` to update the editor content when the current file changes.

5.  **Bug #5 — File IDs Restart on Reset (Fixed):**
    *   Modified `lib/providers/project_provider.dart` to preserve file IDs across app restarts, ensuring the last opened file can be restored.

6.  **Bug #6 — Settings (Font Size, Theme, etc.) Reset on Every App Launch (Fixed):**
    *   Integrated `shared_preferences` in `lib/providers/editor_provider.dart` and `lib/providers/project_provider.dart` to persist editor settings and the last opened project/file.

7.  **Bug #7 — Incorrect Python Version Shown in Status Bar (Fixed):**
    *   Updated `lib/screens/main_screen.dart` to correctly retrieve and display the Python version from the `LinuxEnvironmentProvider`.
