| API | supports modifiers-only shortcuts | event propagation | works through Secure Input | can work from background thread | Requires Input Monitoring permission |
|---|---|---|---|---|---|
| `CGEvent.tapCreate` | **Yes** | **Can propagate or not** | No (modifiers work) | **Yes** | **No** |
| `RegisterEventHotKey`/`InstallEventHandler` | No | Can't propagate; but not needed | **Yes** | No | **No** |
| `NSEvent.addGlobalMonitorForEvents ` | **Yes** | Can't propagate | No (modifiers work) | No | **No** |
| `CGSSetHotModifierWithExclusion` + `CGSSetHotKeyWithExclusion` | **Yes** | Can't propagate | **Yes** | No | **No** |
| `IOHIDManagerRegisterInputValueCallback` | **Yes** | ? | No (modifiers work) | **Yes** | Yes |

Also to consider:

* macOS may send keyboard events disordered
* macOS may not send some keyboard events (e.g. when under heavy load)
* when macOS sends an event, other APIs may disagree (e.g. receiving a keyDown event for `shift`. Calling `NSEvent.modifierFlags` can return that `shift` is down, or that it's not down. It's data-racy.
