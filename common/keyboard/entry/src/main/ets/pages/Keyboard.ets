// The keyboard: English QWERTY, Bulgarian phonetic (the phone arrangement of ЯВЕРТЪ) and a symbols page. Colors come
// from the system theme and icons from HarmonyOS's symbol set, so it follows light and dark mode like Celia Keyboard.
import { inputMethodEngine } from '@kit.IMEKit';
import { KeyboardState } from '../model/KeyboardState';
import { KEY_GAP, KEY_HEIGHT, PAD_BOTTOM, PAD_TOP, ROW_GAP } from '../model/Layout';

const EN_ROWS: string[][] = [
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
  ['z', 'x', 'c', 'v', 'b', 'n', 'm']
];
const BG_ROWS: string[][] = [
  ['я', 'в', 'е', 'р', 'т', 'ъ', 'у', 'и', 'о', 'п', 'ч'],
  ['а', 'с', 'д', 'ф', 'г', 'х', 'й', 'к', 'л', 'ш', 'щ'],
  ['з', 'ь', 'ц', 'ж', 'б', 'н', 'м', 'ю']
];
const SYM_ROWS: string[][] = [
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
  ['@', '#', '€', '%', '&', '-', '+', '(', ')', '/'],
  ['*', '"', '\'', ':', ';', '!', '?', '_']
];
// Long press on the top letter row types these.
const DIGITS: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];

const DOUBLE_TAP_MS = 350;

enum Shift { OFF, ONCE, LOCKED }

enum Kind { CHAR, FN, ACCENT }

const LONG_PRESS_MS = 400;
const REPEAT_DELAY_MS = 350;
const REPEAT_MS = 60;

// The key whose finger is still down. Keys type when their finger lifts, but when the next finger lands first (fast
// typing rolls over), the held key types right then, so both letters come out and in the order they were pressed.
// This also makes shift work as a chord: hold it, tap a letter.
class HeldKey {
  commit: () => void = () => {};
}

let held: HeldKey | undefined = undefined;

@Component
struct KeyCap {
  @Prop label: string = '';
  @Prop hint: string = '';
  @Prop kind: Kind = Kind.CHAR;
  @Prop active: boolean = false;
  @Prop fontSize: number = 23;
  // Width relative to a letter key. Set here, not with .layoutWeight() on KeyCap: that doesn't reach the root Stack.
  @Prop weight: number = 1;
  @Prop icon: Resource | undefined = undefined;
  onTap: () => void = () => {};
  onLongPress: (() => void) | undefined = undefined;
  repeat: boolean = false;
  @State private pressed: boolean = false;
  private touchId: number = -1;
  private done: boolean = false;
  private longTimer: number = -1;
  private repeatTimer: number = -1;
  private holder: HeldKey = new HeldKey();

  aboutToDisappear(): void {
    this.stopTimers();
    if (held === this.holder) {
      held = undefined;
    }
  }

  private stopTimers(): void {
    if (this.longTimer >= 0) {
      clearTimeout(this.longTimer);
      this.longTimer = -1;
    }
    if (this.repeatTimer >= 0) {
      clearInterval(this.repeatTimer);
      this.repeatTimer = -1;
    }
  }

  // Types the key once per press: on lift, or earlier when another finger lands. Not after a long press.
  private commit(): void {
    if (this.done) {
      return;
    }
    this.done = true;
    this.stopTimers();
    this.onTap();
  }

  private longPress(): void {
    this.longTimer = -1;
    this.done = true;
    if (this.onLongPress !== undefined) {
      this.onLongPress();
    }
    if (this.repeat) {
      this.repeatTimer = setInterval(() => {
        if (this.onLongPress !== undefined) {
          this.onLongPress();
        }
      }, REPEAT_MS);
    }
  }

  // Raw touches rather than onClick and LongPressGesture: ArkUI's gestures give up when a second finger lands, so
  // overlapping presses on different keys used to lose letters. Each key follows its own finger by touch id.
  private handleTouch(event: TouchEvent): void {
    for (const t of event.changedTouches) {
      if (t.type === TouchType.Down && this.touchId < 0) {
        if (held !== undefined && held !== this.holder) {
          held.commit();
        }
        held = this.holder;
        this.holder.commit = () => this.commit();
        this.touchId = t.id;
        this.done = false;
        this.pressed = true;
        if (this.onLongPress !== undefined) {
          this.longTimer = setTimeout(() => this.longPress(), this.repeat ? REPEAT_DELAY_MS : LONG_PRESS_MS);
        }
      } else if (t.id === this.touchId && (t.type === TouchType.Up || t.type === TouchType.Cancel)) {
        if (held === this.holder) {
          held = undefined;
        }
        if (t.type === TouchType.Up) {
          this.commit();
        }
        this.stopTimers();
        this.touchId = -1;
        this.pressed = false;
      }
    }
  }

  private capColor(): ResourceColor {
    if (this.pressed) {
      return $r('sys.color.interactive_pressed');
    }
    if (this.kind === Kind.ACCENT) {
      return $r('sys.color.comp_background_emphasize');
    }
    if (this.kind === Kind.FN && !this.active) {
      return $r('sys.color.comp_background_tertiary');
    }
    return $r('sys.color.comp_background_primary');
  }

  private inkColor(): ResourceColor {
    return this.kind === Kind.ACCENT ? $r('sys.color.font_on_primary') : $r('sys.color.font_primary');
  }

  build() {
    Stack() {
      if (this.icon !== undefined) {
        SymbolGlyph(this.icon)
          .fontSize(21)
          .fontColor([this.inkColor()])
          .fontWeight(this.active ? FontWeight.Bold : FontWeight.Regular)
      } else {
        Text(this.label)
          .fontSize(this.fontSize)
          .fontColor(this.inkColor())
          .fontWeight(this.kind === Kind.CHAR ? FontWeight.Regular : FontWeight.Medium)
      }
      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(10)
          .fontColor($r('sys.color.font_secondary'))
          .position({ top: 3, right: 5 })
      }
    }
    .layoutWeight(this.weight)
    .height(KEY_HEIGHT)
    .margin({ left: KEY_GAP / 2, right: KEY_GAP / 2 })
    .borderRadius(8)
    .backgroundColor(this.capColor())
    .shadow({ radius: 0.5, color: $r('app.color.kb_shadow'), offsetY: 1 })
    .onTouch((event: TouchEvent) => this.handleTouch(event))
  }
}

@Entry
@Component
struct Keyboard {
  @StorageLink('kbLang') lang: string = 'en';
  @StorageLink('kbEnter') enterType: number = 0;
  @State shift: Shift = Shift.OFF;
  @State symbols: boolean = false;
  private lastShiftTap: number = 0;

  private rows(): string[][] {
    if (this.symbols) {
      return SYM_ROWS;
    }
    return this.lang === 'bg' ? BG_ROWS : EN_ROWS;
  }

  // Long press on the top letter row types a digit; its hint shows in the key's corner.
  private digitHint(row: number, i: number): string {
    return (row === 0 && !this.symbols && i < DIGITS.length) ? DIGITS[i] : '';
  }

  private caps(ch: string): string {
    return (!this.symbols && this.shift !== Shift.OFF) ? ch.toUpperCase() : ch;
  }

  private type(text: string): void {
    KeyboardState.insert(text);
    if (this.shift === Shift.ONCE) {
      this.shift = Shift.OFF;
    }
  }

  private tapShift(): void {
    const now = Date.now();
    if (this.shift === Shift.LOCKED) {
      this.shift = Shift.OFF;
    } else if (now - this.lastShiftTap < DOUBLE_TAP_MS) {
      this.shift = Shift.LOCKED;
    } else {
      this.shift = this.shift === Shift.OFF ? Shift.ONCE : Shift.OFF;
    }
    this.lastShiftTap = now;
  }

  private enterIcon(): Resource {
    switch (this.enterType) {
      case inputMethodEngine.ENTER_KEY_TYPE_SEARCH:
        return $r('sys.symbol.magnifyingglass');
      case inputMethodEngine.ENTER_KEY_TYPE_SEND:
        return $r('sys.symbol.paperplane_fill');
      case inputMethodEngine.ENTER_KEY_TYPE_DONE:
        return $r('sys.symbol.checkmark');
      case inputMethodEngine.ENTER_KEY_TYPE_GO:
      case inputMethodEngine.ENTER_KEY_TYPE_NEXT:
        return $r('sys.symbol.arrow_right');
      case inputMethodEngine.ENTER_KEY_TYPE_PREVIOUS:
        return $r('sys.symbol.arrow_left');
      default:
        return $r('sys.symbol.return_down_left');
    }
  }

  // Search, send, go and the like are actions: the key is drawn in the accent color, as on the system keyboard.
  private enterIsAction(): boolean {
    return this.enterType >= inputMethodEngine.ENTER_KEY_TYPE_GO &&
      this.enterType <= inputMethodEngine.ENTER_KEY_TYPE_PREVIOUS;
  }

  // Takes the row number and reads the layout state itself: a @Builder's plain arguments are evaluated once, so a
  // row passed in as an array never redrew when the language or the symbols page changed.
  @Builder
  letterRow(row: number) {
    ForEach(this.rows()[row], (ch: string, i: number) => {
      KeyCap({
        label: this.caps(ch),
        hint: this.digitHint(row, i),
        onTap: () => this.type(this.caps(ch)),
        onLongPress: this.digitHint(row, i).length > 0 ? () => KeyboardState.insert(DIGITS[i]) : undefined
      })
    }, (ch: string) => ch + this.shift + this.lang + this.symbols)
  }

  build() {
    Column({ space: ROW_GAP }) {
      Row() {
        this.letterRow(0)
      }.width('100%')

      Row() {
        if (this.rows()[1].length < this.rows()[0].length) {
          Blank().layoutWeight(0.5)
        }
        this.letterRow(1)
        if (this.rows()[1].length < this.rows()[0].length) {
          Blank().layoutWeight(0.5)
        }
      }.width('100%')

      Row() {
        if (!this.symbols) {
          KeyCap({
            kind: Kind.FN,
            active: this.shift !== Shift.OFF,
            icon: this.shift === Shift.LOCKED ? $r('sys.symbol.arrow_up_to_line') : $r('sys.symbol.arrow_up'),
            onTap: () => this.tapShift(),
            weight: 1.45
          })
        } else {
          Blank().layoutWeight(1.45)
        }
        this.letterRow(2)
        KeyCap({
          kind: Kind.FN,
          icon: $r('sys.symbol.delete_left'),
          onTap: () => KeyboardState.backspace(),
          onLongPress: () => KeyboardState.backspace(),
          repeat: true,
          weight: 1.45
        })
      }.width('100%')

      Row() {
        KeyCap({
          kind: Kind.FN,
          label: this.symbols ? 'ABC' : '?123',
          fontSize: 15,
          onTap: () => {
            this.symbols = !this.symbols;
          },
          weight: 1.4
        })
        KeyCap({
          kind: Kind.FN,
          icon: $r('sys.symbol.worldclock'),
          onTap: () => {
            KeyboardState.setLanguage(this.lang === 'bg' ? 'en' : 'bg');
            this.symbols = false;
          },
          weight: 1.1
        })
        KeyCap({ label: ',', onTap: () => KeyboardState.insert(',') })
        KeyCap({
          label: this.lang === 'bg' ? 'Български' : 'English',
          fontSize: 14,
          onTap: () => KeyboardState.insert(' '),
          weight: 4.2
        })
        KeyCap({ label: '.', onTap: () => KeyboardState.insert('.') })
        KeyCap({
          kind: this.enterIsAction() ? Kind.ACCENT : Kind.FN,
          icon: this.enterIcon(),
          onTap: () => KeyboardState.enter(),
          weight: 1.6
        })
      }.width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 4, right: 4, top: PAD_TOP, bottom: PAD_BOTTOM })
    .justifyContent(FlexAlign.Start)
    // The color of the system's IME bar below the panel (measured: #E5E6E7 in light mode), so the two read as one.
    .backgroundColor($r('app.color.kb_panel'))
  }
}
