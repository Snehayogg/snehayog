# Vayug Project Instructions

This file contains team-shared architecture, conventions, workflows, and other repo guidance for the Vayug project.

## Core Mandates

- **Backend-Driven Architecture:** Prioritize server-side control over UI and business logic where feasible to enable rapid updates without client-side releases.
- **Performance First:** Aggressive caching (Redis), optimized video streaming (HLS), and memory management (Flutter controller pooling) are non-negotiable.
- **Security:** Rigorously protect API keys, secrets, and user data. Never log sensitive information.

## Architecture & Conventions

### Backend (Node.js/Express)
- **Structure:** `Controller -> Service -> Model`. No business logic in controllers.
- **Async/Await:** Use `async/await` for all asynchronous operations. Handle errors with `try/catch` or a global error handler.
- **Database:** MongoDB for persistent storage, Redis for high-frequency reads and feed caching.
- **Validation:** Use Joi or similar for request validation.

### Frontend (Flutter)
- **State Management:** Riverpod is the preferred state management solution.
- **Clean Architecture:** Organise code by features: `domain -> data -> presentation`.
- **UI/UX:** Focus on "fluid" interactions. Use custom animations and transitions to match the "TikTok-style" experience.
- **Asset Management:** Use lazy loading for images and videos. Image cache is limited to 100MB for low-RAM devices.

## Workflows

- **Feature Development:**
  1. Define the API contract.
  2. Implement backend services and routes.
  3. Implement frontend features using Riverpod.
  4. Verify on both Android and iOS (if applicable).
- **Testing:**
  - Backend: `npm test` in `backend/` directory.
  - Frontend: `flutter test` in `frontend/` directory.
- **Deployment:** Backend is deployed via Fly.io. Edge logic lives in Cloudflare Workers.

## Reference Documentation

- [CLAUDE.md](./CLAUDE.md) - Project overview and technical deep-dive.
- [ARCHITECTURE.md](./frontend/ARCHITECTURE.md) - Frontend-specific architectural details.
- [BACKEND_DRIVEN_ARCHITECTURE.md](./backend/docs/BACKEND_DRIVEN_ARCHITECTURE.md) - Core backend philosophy.
