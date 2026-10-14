// Every text field's editing: typing over a selection, the word and line
// deletes, caret moves with and without Shift, the clipboard shortcuts, and a
// masked field that never hands its text out.

use fs_menu::field::{Field, Key, Outcome};
use fs_menu::nav::Modifiers;

const NONE: Modifiers = Modifiers { ctrl: false, shift: false, alt: false };
const CTRL: Modifiers = Modifiers { ctrl: true, shift: false, alt: false };
const SHIFT: Modifiers = Modifiers { ctrl: false, shift: true, alt: false };
const CTRL_SHIFT: Modifiers = Modifiers { ctrl: true, shift: true, alt: false };

fn field(s: &str) -> Field {
    Field::new(s.to_owned())
}

fn ctrl(f: &mut Field, c: char) -> Outcome {
    f.key(Key::Letter(c), CTRL, None)
}

#[test]
fn typing_lands_at_the_caret() {
    let mut f = field("helo");
    f.key(Key::Left, NONE, None);
    assert_eq!(f.key(Key::Letter('l'), NONE, Some("l")), Outcome::Edited);
    assert_eq!(f.text(), "hello");
    assert_eq!(f.caret(), 4);
}

#[test]
fn ctrl_a_then_typing_replaces_everything() {
    let mut f = field("firefox");
    assert_eq!(ctrl(&mut f, 'a'), Outcome::Held);
    assert_eq!(f.selection(), Some((0, 7)));
    f.key(Key::Other, NONE, Some("k"));
    assert_eq!(f.text(), "k");
    assert_eq!(f.selection(), None);
}

#[test]
fn ctrl_a_then_backspace_or_delete_empties_it() {
    let mut f = field("hunter2");
    ctrl(&mut f, 'a');
    assert_eq!(f.key(Key::Backspace, NONE, None), Outcome::Edited);
    assert!(f.is_empty());
    let mut f = field("hunter2");
    ctrl(&mut f, 'a');
    assert_eq!(f.key(Key::Delete, NONE, None), Outcome::Edited);
    assert!(f.is_empty());
}

#[test]
fn backspace_and_delete_take_one_char_either_side() {
    let mut f = field("abc");
    f.key(Key::Left, NONE, None);
    f.key(Key::Backspace, NONE, None);
    assert_eq!(f.text(), "ac");
    f.key(Key::Delete, NONE, None);
    assert_eq!(f.text(), "a");
    assert_eq!(f.key(Key::Delete, NONE, None), Outcome::Held);
}

#[test]
fn ctrl_backspace_deletes_the_word_and_the_space_after_it() {
    let mut f = field("foo bar ");
    f.key(Key::Backspace, CTRL, None);
    assert_eq!(f.text(), "foo ");
    f.key(Key::Backspace, CTRL, None);
    assert_eq!(f.text(), "");
}

#[test]
fn ctrl_delete_deletes_the_next_word() {
    let mut f = field("foo bar baz");
    f.key(Key::Home, NONE, None);
    f.key(Key::Right, CTRL, None);
    assert_eq!(f.caret(), 3);
    f.key(Key::Delete, CTRL, None);
    assert_eq!(f.text(), "foo baz");
}

#[test]
fn ctrl_left_and_right_walk_words() {
    let mut f = field("one two  three");
    f.key(Key::Left, CTRL, None);
    assert_eq!(f.caret(), 9);
    f.key(Key::Left, CTRL, None);
    assert_eq!(f.caret(), 4);
    f.key(Key::Left, CTRL, None);
    assert_eq!(f.caret(), 0);
    f.key(Key::Left, CTRL, None);
    assert_eq!(f.caret(), 0);
    f.key(Key::Right, CTRL, None);
    assert_eq!(f.caret(), 3);
    f.key(Key::Right, CTRL, None);
    assert_eq!(f.caret(), 7);
}

#[test]
fn shift_extends_and_a_plain_arrow_collapses_to_that_side() {
    let mut f = field("abcdef");
    f.key(Key::Left, SHIFT, None);
    f.key(Key::Left, SHIFT, None);
    assert_eq!(f.selection(), Some((4, 6)));
    f.key(Key::Home, SHIFT, None);
    assert_eq!(f.selection(), Some((0, 6)));
    f.key(Key::Right, NONE, None);
    assert_eq!((f.caret(), f.selection()), (6, None));
    f.key(Key::Left, CTRL_SHIFT, None);
    assert_eq!(f.selection(), Some((0, 6)));
    f.key(Key::Left, NONE, None);
    assert_eq!((f.caret(), f.selection()), (0, None));
}

#[test]
fn home_and_end_jump() {
    let mut f = field("abc");
    f.key(Key::Home, NONE, None);
    assert_eq!(f.caret(), 0);
    f.key(Key::End, NONE, None);
    assert_eq!(f.caret(), 3);
}

#[test]
fn multibyte_text_steps_by_char() {
    let mut f = field("añ😭b");
    f.key(Key::Left, NONE, None);
    f.key(Key::Backspace, NONE, None);
    assert_eq!(f.text(), "añb");
    f.key(Key::Left, SHIFT, None);
    assert_eq!(f.caret_chars(), (1, 2));
    f.key(Key::Delete, NONE, None);
    assert_eq!(f.text(), "ab");
    let mut f = field("日本 語");
    f.key(Key::Backspace, CTRL, None);
    assert_eq!(f.text(), "日本 ");
    f.key(Key::Left, CTRL, None);
    assert_eq!(f.caret(), 0);
}

#[test]
fn ctrl_u_clears() {
    let mut f = field("abc");
    assert_eq!(ctrl(&mut f, 'u'), Outcome::Edited);
    assert!(f.is_empty());
    assert_eq!(ctrl(&mut f, 'u'), Outcome::Held);
}

#[test]
fn copy_and_cut_hand_out_the_selection() {
    let mut f = field("hello world");
    f.key(Key::Left, CTRL_SHIFT, None);
    assert_eq!(ctrl(&mut f, 'c'), Outcome::Copy("world".into()));
    assert_eq!(f.text(), "hello world");
    assert_eq!(ctrl(&mut f, 'x'), Outcome::Cut("world".into()));
    assert_eq!(f.text(), "hello ");
    assert_eq!(ctrl(&mut f, 'c'), Outcome::Held);
}

#[test]
fn a_secret_field_never_hands_its_text_out() {
    let mut f = field("hunter2").secret();
    ctrl(&mut f, 'a');
    assert_eq!(ctrl(&mut f, 'c'), Outcome::Held);
    assert_eq!(ctrl(&mut f, 'x'), Outcome::Held);
    assert_eq!(f.text(), "hunter2");
}

#[test]
fn paste_is_asked_for_and_lands_flat_over_the_selection() {
    let mut f = field("abc");
    assert_eq!(ctrl(&mut f, 'v'), Outcome::Paste);
    f.key(Key::Left, SHIFT, None);
    assert!(f.paste("one\ntwo\r\n"));
    assert_eq!(f.text(), "abone two");
    assert!(!f.paste("\n"));
}

#[test]
fn control_text_and_other_shortcuts_pass() {
    let mut f = field("abc");
    assert_eq!(f.key(Key::Other, NONE, Some("\u{1}")), Outcome::Pass);
    assert_eq!(f.key(Key::Letter('k'), CTRL, None), Outcome::Pass);
    assert_eq!(f.key(Key::Other, NONE, None), Outcome::Pass);
    assert_eq!(f.key(Key::Left, Modifiers { alt: true, ..NONE }, None), Outcome::Pass);
    assert_eq!(f.text(), "abc");
}

#[test]
fn set_and_replace_put_the_caret_at_the_end() {
    let mut f = field("");
    f.set("query");
    assert_eq!(f.caret(), 5);
    ctrl(&mut f, 'a');
    let old = f.replace(String::new());
    assert_eq!((old.as_str(), f.text(), f.selection()), ("query", "", None));
}
