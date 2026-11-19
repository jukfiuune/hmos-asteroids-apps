// State shared between the input method service (which owns the connection to the text field) and the keyboard page
// (which runs in the panel's UI). Both live in the same process and ArkTS runtime.
import { inputMethodEngine } from '@kit.IMEKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0xA5A5;
const TAG = 'AsteroidsKeyboard';

function logFailure(what: string): (e: BusinessError) => void {
  return (e: BusinessError) => hilog.warn(DOMAIN, TAG, '%{public}s failed: %{public}d', what, e.code);
}

export class KeyboardState {
  static client: inputMethodEngine.InputClient | undefined = undefined;

  static insert(text: string): void {
    KeyboardState.client?.insertText(text).catch(logFailure('insertText'));
  }

  static backspace(): void {
    // deleteForward removes text before the cursor.
    KeyboardState.client?.deleteForward(1).catch(logFailure('deleteForward'));
  }

  static enter(): void {
    const t = KeyboardState.enterKeyType();
    if (t === inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED || t === inputMethodEngine.ENTER_KEY_TYPE_NEWLINE ||
      t === 1 /* NONE */) {
      KeyboardState.insert('\n');
    } else {
      KeyboardState.client?.sendKeyFunction(t).catch(logFailure('sendKeyFunction'));
    }
  }

  // The page reads these through AppStorage so it redraws when they change.
  static setLanguage(lang: string): void {
    AppStorage.setOrCreate<string>('kbLang', lang);
  }

  static setEnterKeyType(t: number): void {
    AppStorage.setOrCreate<number>('kbEnter', t);
  }

  static enterKeyType(): number {
    return AppStorage.get<number>('kbEnter') ?? inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED;
  }
}
