# Snehayog App - Modular Architecture

This document describes the new modular + layered architecture implemented in the Snehayog Flutter application.

## Architecture Overview

The app follows **Clean Architecture** principles with **Feature-based modules** and **Layered architecture**:

```
lib/
├── core/                    # Shared infrastructure
│   ├── constants/          # App-wide constants
│   ├── enums/             # Shared enums
│   ├── exceptions/        # Centralized exception handling
│   ├── network/           # Network configuration and helpers
│   ├── di/                # Dependency injection
│   └── utils/             # Shared utilities
├── features/               # Feature-based modules
│   ├── auth/              # Authentication feature
│   │   ├── data/          # Data layer (repositories, datasources)
│   │   ├── domain/        # Domain layer (entities, use cases, repositories)
│   │   └── presentation/  # Presentation layer (providers, screens, widgets)
│   ├── video/             # Video feature
│   │   ├── data/          # Data layer
│   │   ├── domain/        # Domain layer
│   │   └── presentation/  # Presentation layer
│   └── profile/           # Profile feature
│       ├── data/          # Data layer
│       ├── domain/        # Domain layer
│       └── presentation/  # Presentation layer
└── shared/                 # Shared components
    ├── widgets/            # Reusable UI components
    └── services/           # Shared services
```

## Layer Responsibilities

### 1. Domain Layer (Business Logic)
- **Entities**: Core business objects (e.g., `VideoEntity`, `CommentEntity`)
- **Use Cases**: Business logic operations (e.g., `GetVideosUseCase`, `UploadVideoUseCase`)
- **Repository Interfaces**: Abstract contracts for data operations

### 2. Data Layer (Data Management)
- **Data Sources**: Remote/local data providers (e.g., `VideoRemoteDataSource`)
- **Models**: Data transfer objects that extend domain entities
- **Repository Implementations**: Concrete implementations of repository interfaces

### 3. Presentation Layer (UI & State)
- **Providers**: State management using `ChangeNotifier`
- **Screens**: Full-page UI components
- **Widgets**: Reusable UI components specific to the feature

## Key Benefits

### 1. **Modularity**
- Each feature is self-contained with its own layers
- Features can be developed, tested, and maintained independently
- Easy to add new features without affecting existing ones

### 2. **Separation of Concerns**
- Clear boundaries between business logic, data, and presentation
- Each layer has a single responsibility
- Easy to understand and maintain

### 3. **Testability**
- Business logic is isolated from UI and data
- Each layer can be tested independently
- Easy to mock dependencies for unit tests

### 4. **Scalability**
- New features can be added without modifying existing code
- Team members can work on different features simultaneously
- Code is organized in logical, manageable chunks

### 5. **Maintainability**
- Files are kept under 400-500 lines as per team preference
- Clear dependency flow makes debugging easier
- Consistent patterns across all features

## Dependency Flow

```
Presentation Layer → Domain Layer ← Data Layer
       ↓                    ↑           ↑
   UI Widgets         Use Cases    Data Sources
   Providers          Entities     Models
```

- **Presentation** depends on **Domain** (use cases, entities)
- **Data** implements **Domain** (repositories, models)
- **Domain** is independent of other layers
- **Core** provides shared infrastructure

## Implementation Details

### Exception Handling
- Centralized in `core/exceptions/app_exceptions.dart`
- Custom exception types for different error scenarios
- Consistent error handling across all layers

### Network Configuration
- Centralized in `core/network/network_helper.dart`
- Environment-based configuration (dev/prod)
- Consistent timeout and retry policies

### Dependency Injection
- Lightweight service locator pattern in `core/di/dependency_injection.dart`
- Lazy initialization of services
- Easy to manage dependencies without external libraries

### State Management
- Uses `ChangeNotifier` for efficient state updates
- Follows the ValueNotifier pattern to avoid unnecessary rebuilds
- Optimistic UI updates for better user experience

## Migration Guide

### From Old Structure
1. **Move existing code** to appropriate feature modules
2. **Extract business logic** into use cases
3. **Create domain entities** for core business objects
4. **Implement repository pattern** for data operations
5. **Update UI components** to use new providers

### File Organization
- Keep each file under 400-500 lines
- Split large files into smaller, focused modules
- Use consistent naming conventions across layers

## Best Practices

### 1. **Naming Conventions**
- Entities: `VideoEntity`, `CommentEntity`
- Use Cases: `GetVideosUseCase`, `UploadVideoUseCase`
- Repositories: `VideoRepository`, `VideoRepositoryImpl`
- Data Sources: `VideoRemoteDataSource`
- Models: `VideoModel`, `CommentModel`

### 2. **Error Handling**
- Use custom exceptions for different error types
- Handle errors at the appropriate layer
- Provide user-friendly error messages

### 3. **Performance**
- Use `const` constructors for immutable widgets
- Implement lazy loading for large lists
- Cache frequently accessed data

### 4. **Testing**
- Write unit tests for use cases
- Mock repositories for testing
- Test UI components in isolation

## Future Enhancements

### 1. **Additional Features**
- User management module
- Analytics module
- Notification module

### 2. **Advanced Patterns**
- Event-driven architecture
- CQRS pattern for complex operations
- Repository pattern with local caching

### 3. **Performance Optimizations**
- Image and video caching
- Lazy loading strategies
- Background processing

## Conclusion

This modular architecture provides a solid foundation for building a scalable, maintainable Flutter application. It follows industry best practices and makes the codebase easier to understand, test, and extend.

The separation of concerns and clear dependency flow will help the team work more efficiently and deliver higher quality code.
