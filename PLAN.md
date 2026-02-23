# Self-Test Framework Development Plan

## Overview
This plan outlines the development strategy for the self-test framework, focusing on ease of integration, robust reporting, and proper memory management. The framework provides infrastructure for testing Flutter apps, while leaving test logic implementation to developers (similar to Playwright).

## Current Status
- ✅ Widget coverage assessment completed
- ✅ Missing native widgets identified
- 🔄 Extensible widget handling design in progress

## Key Principles
1. **Ease of Integration**: Simple wrapper widgets and mode activation
2. **Strong Reporting**: Detailed logging, code export, test script management
3. **Memory Management**: Proper registration/unregistration of test nodes
4. **Extensibility**: Allow developers to register custom widget handlers
5. **Developer Responsibility**: Test logic implementation is left to dev testers

## Detailed Tasks

### 1. Design Extensible Widget Handling
**Status**: In Progress  
**Description**: Create a registry system for widget recording builders. Use a `Map<Type, Widget Function(Widget, SelfTestableWidget)>` in `SelfTestManager` with a `registerRecordingBuilder<T>()` method for custom handlers.

**Goals**:
- Allow devs to extend support for custom/3rd-party widgets
- Maintain backward compatibility with existing hardcoded handlers
- Keep package code simple and focused

### 2. Implement Fallback for Unknown Widgets
**Status**: Not Started  
**Description**: For widgets without specific handlers, provide intelligent fallback behavior.

**Implementation**:
- Check if `SelfTestableWidget` has `onTap` callback
- Wrap unknown widgets in `GestureDetector` if tappable
- Return widget as-is with debug warning for extensibility
- Ensure proper cleanup in widget lifecycle

### 3. Add Support for Key Missing Widgets
**Status**: Not Started  
**Description**: Add recording support for high-priority Flutter widgets.

**Target Widgets**:
- `FloatingActionButton`
- `TextFormField`
- `DropdownButton`
- `SegmentedButton`
- `PopupMenuButton`
- `ExpansionTile`

**Pattern**: Follow existing implementation pattern with intercepted callbacks.

### 4. Document Extensibility for Developers
**Status**: Not Started  
**Description**: Create comprehensive documentation for extending the framework.

**Content**:
- How to register custom recording builders
- Examples for custom/3rd-party widgets
- Best practices for test logic implementation
- API reference for extension points

### 5. Test Extensibility and Edge Cases
**Status**: Not Started  
**Description**: Validate the framework with various scenarios.

**Test Scenarios**:
- Mixed widget types in single screen
- Custom widget registration
- Memory leak prevention
- Recording/playback accuracy
- Integration with different app architectures

### 6. Improve Reporting and Export Features
**Status**: Not Started  
**Description**: Enhance developer experience with better feedback.

**Features**:
- Enhanced debug logging with timestamps
- Multiple export formats (Dart code, JSON)
- Test script versioning and management
- Visual feedback improvements
- Integration with CI/CD pipelines

### 7. Optimize Memory Management
**Status**: Not Started  
**Description**: Ensure robust instance lifecycle management.

**Focus Areas**:
- Automatic node registration/unregistration
- Weak references for context handling
- Memory leak detection in tests
- Proper cleanup on hot reload
- Performance monitoring

## Implementation Priority
1. Complete extensible architecture design
2. Implement fallback system
3. Add key missing widgets
4. Enhance reporting features
5. Optimize memory management
6. Comprehensive testing
7. Documentation

## Success Criteria
- Easy integration: < 5 minutes setup for new projects
- Extensible: Support for any widget type via registration
- Memory-safe: No leaks in typical usage scenarios
- Developer-friendly: Clear APIs and comprehensive docs
- Production-ready: Stable for complex Flutter apps

## Risks and Mitigations
- **New Flutter widgets**: Extensible architecture mitigates breaking changes
- **Performance impact**: Lazy registration and proper cleanup
- **Complexity**: Keep core simple, extensibility optional
- **Memory leaks**: Comprehensive testing and monitoring

## Next Steps
1. Finalize extensible architecture design
2. Implement registry system
3. Create fallback mechanism
4. Add documentation
5. Begin implementation of missing widgets