//! `pam_probe <service> <user>`: authenticates once with the password on the
//! first line of stdin and prints every event. Exits 0 only on success.

use std::io::BufRead;

use fs_auth::pam::{Conversation, Event, Message, Outcome};
use zeroize::Zeroizing;

fn main() {
    let mut args = std::env::args().skip(1);
    let (Some(service), Some(user)) = (args.next(), args.next()) else {
        eprintln!("usage: pam_probe <service> <user>");
        std::process::exit(2);
    };
    let mut line = Zeroizing::new(String::new());
    std::io::stdin().lock().read_line(&mut line).expect("read stdin");
    let password = Zeroizing::new(line.trim_end_matches('\n').to_owned());
    drop(line);

    let conversation = Conversation::start(&service, &user).expect("start conversation");
    let mut password = Some(password);
    let outcome = futures_lite::future::block_on(async {
        loop {
            match conversation.next().await {
                Some(Event::Message(Message::Prompt { text, echo })) => {
                    println!("prompt echo={echo} {text:?}");
                    let answer = password.take().unwrap_or_default();
                    conversation.respond(answer);
                }
                Some(Event::Message(message)) => println!("message {message:?}"),
                Some(Event::Done(outcome)) => break outcome,
                None => panic!("conversation ended without a result"),
            }
        }
    });
    println!("outcome {outcome:?}");
    std::process::exit(if outcome == Outcome::Success { 0 } else { 1 });
}
