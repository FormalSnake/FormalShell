//! A PAM conversation for the lock screen: one `pam_authenticate` run on its
//! own thread, its messages and result posted back over a channel.

use std::ffi::{CStr, CString};
use std::thread;

use async_channel::{Receiver, Sender};
use pam_client2::{Context, ConversationHandler, ErrorCode, Flag};
use zeroize::{Zeroize, Zeroizing};

pub const LOCK_SERVICE: &str = "formalshell-lock";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Message {
    /// A prompt that needs `Conversation::respond`. `echo` is false for a
    /// password.
    Prompt { text: String, echo: bool },
    Info(String),
    Error(String),
}

/// How `pam_authenticate` ended. The strings are PAM's own `pam_strerror`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    Success,
    /// `PAM_AUTH_ERR`: the wrong password.
    Failed(String),
    /// `PAM_MAXTRIES`: a module has locked the account for now.
    MaxTries(String),
    /// `pam_start` failed, usually a service with no file under /etc/pam.d.
    StartFailed(String),
    /// Any other PAM error.
    Error(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Message(Message),
    Done(Outcome),
}

/// One authentication attempt. Dropping it aborts a conversation waiting on
/// a response: the pending prompt answers `PAM_CONV_ERR` and the thread ends.
pub struct Conversation {
    events: Receiver<Event>,
    responses: Sender<Zeroizing<String>>,
}

impl Conversation {
    pub fn start(service: &str, user: &str) -> std::io::Result<Self> {
        let (event_tx, events) = async_channel::unbounded();
        let (responses, response_rx) = async_channel::bounded(1);
        let service = service.to_owned();
        let user = user.to_owned();
        thread::Builder::new()
            .name("fs-pam".into())
            .spawn(move || {
                let outcome = authenticate(&service, &user, &event_tx, response_rx);
                let _ = event_tx.send_blocking(Event::Done(outcome));
            })?;
        Ok(Self { events, responses })
    }

    /// The next message, then exactly one `Event::Done`, then `None`.
    pub async fn next(&self) -> Option<Event> {
        self.events.recv().await.ok()
    }

    /// Answers the pending prompt. False when the conversation has ended.
    pub fn respond(&self, response: Zeroizing<String>) -> bool {
        self.responses.try_send(response).is_ok()
    }
}

fn authenticate(
    service: &str,
    user: &str,
    events: &Sender<Event>,
    responses: Receiver<Zeroizing<String>>,
) -> Outcome {
    let handler = Handler { events: events.clone(), responses };
    let mut context = match Context::new(service, Some(user), handler) {
        Ok(context) => context,
        Err(err) => return Outcome::StartFailed(describe(err.code(), err.message())),
    };
    match context.authenticate(Flag::NONE) {
        Ok(()) => Outcome::Success,
        Err(err) => {
            let text = describe(err.code(), err.message());
            match err.code() {
                ErrorCode::AUTH_ERR => Outcome::Failed(text),
                ErrorCode::MAXTRIES => Outcome::MaxTries(text),
                _ => Outcome::Error(text),
            }
        }
    }
}

fn describe(code: ErrorCode, message: Option<&str>) -> String {
    message.map_or_else(|| format!("{code:?}"), str::to_owned)
}

struct Handler {
    events: Sender<Event>,
    responses: Receiver<Zeroizing<String>>,
}

impl Handler {
    fn ask(&mut self, prompt: &CStr, echo: bool) -> Result<CString, ErrorCode> {
        let text = prompt.to_string_lossy().into_owned();
        self.events
            .send_blocking(Event::Message(Message::Prompt { text, echo }))
            .map_err(|_| ErrorCode::CONV_ERR)?;
        let response = self.responses.recv_blocking().map_err(|_| ErrorCode::CONV_ERR)?;
        to_cstring(response)
    }

    fn tell(&mut self, message: Message) {
        let _ = self.events.send_blocking(Event::Message(message));
    }
}

// pam-client2 takes the answer as a CString and strdup()s it into the buffer
// PAM frees; std zeroes only the first byte of a dropped CString.
fn to_cstring(response: Zeroizing<String>) -> Result<CString, ErrorCode> {
    let mut bytes = Vec::with_capacity(response.len() + 1);
    bytes.extend_from_slice(response.as_bytes());
    drop(response);
    match CString::new(bytes) {
        Ok(cstring) => Ok(cstring),
        Err(err) => {
            err.into_vec().zeroize();
            Err(ErrorCode::CONV_ERR)
        }
    }
}

impl ConversationHandler for Handler {
    fn prompt_echo_on(&mut self, prompt: &CStr) -> Result<CString, ErrorCode> {
        self.ask(prompt, true)
    }

    fn prompt_echo_off(&mut self, prompt: &CStr) -> Result<CString, ErrorCode> {
        self.ask(prompt, false)
    }

    fn text_info(&mut self, msg: &CStr) {
        self.tell(Message::Info(msg.to_string_lossy().into_owned()));
    }

    fn error_msg(&mut self, msg: &CStr) {
        self.tell(Message::Error(msg.to_string_lossy().into_owned()));
    }

    fn radio_prompt(&mut self, prompt: &CStr) -> Result<bool, ErrorCode> {
        let answer = self.ask(prompt, true)?;
        let yes = matches!(answer.as_bytes().first(), Some(b'y' | b'Y'));
        Ok(yes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn interior_nul_is_refused() {
        let answer = to_cstring(Zeroizing::new("a\0b".to_owned()));
        assert_eq!(answer.unwrap_err(), ErrorCode::CONV_ERR);
    }

    #[test]
    fn missing_service_fails_to_start_or_errors() {
        let conversation = Conversation::start("fs-auth-no-such-service", "nobody").unwrap();
        let outcome = futures_lite::future::block_on(async {
            loop {
                match conversation.next().await {
                    Some(Event::Done(outcome)) => break outcome,
                    Some(Event::Message(Message::Prompt { .. })) => {
                        conversation.respond(Zeroizing::new(String::new()));
                    }
                    Some(Event::Message(_)) => {}
                    None => panic!("conversation ended without a result"),
                }
            }
        });
        assert_ne!(outcome, Outcome::Success);
    }
}
