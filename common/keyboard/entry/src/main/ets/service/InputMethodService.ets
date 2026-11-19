// The input method itself: connects to the focused text field and shows the keyboard page in a fixed soft-keyboard
// panel at the bottom of the screen. The system shows and hides that panel with the text field's focus.
import { InputMethodExtensionAbility, InputMethodSubtype, inputMethodEngine } from '@kit.IMEKit';
import { ConfigurationConstant, Want } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyboardState } from '../model/KeyboardState';
import { KEYBOARD_HEIGHT_VP } from '../model/Layout';

const DOMAIN = 0xA5A5;
const TAG = 'AsteroidsKeyboard';

export default class InputMethodService extends InputMethodExtensionAbility {
  private panel: inputMethodEngine.Panel | undefined = undefined;

  onCreate(want: Want): void {
    const ability = inputMethodEngine.getInputMethodAbility();
    ability.on('inputStart', (kb: inputMethodEngine.KeyboardController, client: inputMethodEngine.InputClient) => {
      KeyboardState.client = client;
      this.matchSystemBar();
      client.getEditorAttribute().then((attr: inputMethodEngine.EditorAttribute) => {
        KeyboardState.setEnterKeyType(attr.enterKeyType);
      }).catch(() => {
        KeyboardState.setEnterKeyType(inputMethodEngine.ENTER_KEY_TYPE_UNSPECIFIED);
      });
    });
    ability.on('inputStop', () => {
      KeyboardState.client = undefined;
    });
    ability.on('setSubtype', (subtype: InputMethodSubtype) => {
      KeyboardState.setLanguage(subtype.id === 'bg_phonetic' ? 'bg' : 'en');
    });
    this.createPanel();
  }

  onDestroy(): void {
    if (this.panel !== undefined) {
      inputMethodEngine.getInputMethodAbility().destroyPanel(this.panel);
      this.panel = undefined;
    }
  }

  // The system bar under the keyboard (switcher and settings) takes on the keyboard's look instead of its own gray.
  // Apps pick the light or dark variant (plain IMMERSIVE is refused with 401); checked again each time input starts,
  // so it follows the system's dark mode.
  private matchSystemBar(): void {
    if (this.panel === undefined) {
      return;
    }
    const dark = this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    try {
      this.panel.setImmersiveMode(dark ? inputMethodEngine.ImmersiveMode.DARK_IMMERSIVE :
        inputMethodEngine.ImmersiveMode.LIGHT_IMMERSIVE);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'immersive mode failed: %{public}s', JSON.stringify(e));
    }
  }

  private async createPanel(): Promise<void> {
    try {
      const panel = await inputMethodEngine.getInputMethodAbility().createPanel(this.context, {
        type: inputMethodEngine.PanelType.SOFT_KEYBOARD,
        flag: inputMethodEngine.PanelFlag.FLG_FIXED
      });
      const d = display.getDefaultDisplaySync();
      await panel.resize(d.width, Math.round(KEYBOARD_HEIGHT_VP * d.densityPixels));
      await panel.setUiContent('pages/Keyboard');
      this.panel = panel;
      this.matchSystemBar();
      hilog.info(DOMAIN, TAG, 'panel ready %{public}dx%{public}d', d.width, Math.round(KEYBOARD_HEIGHT_VP * d.densityPixels));
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'panel failed: %{public}s', JSON.stringify(e));
    }
  }
}
