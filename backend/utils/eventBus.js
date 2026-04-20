import { EventEmitter } from 'events';

/**
 * Global Event Bus for inter-module communication.
 * Primarily used for SSE (Server-Sent Events) to notify controllers
 * of background worker progress.
 */
class EventBus extends EventEmitter {}

export default new EventBus();
