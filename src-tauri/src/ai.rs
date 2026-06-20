use serde_json::{json, Value};

#[derive(serde::Deserialize)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

pub fn build_anthropic_body(model: &str, messages: &[ChatMessage]) -> Value {
    let msgs: Vec<Value> = messages
        .iter()
        .map(|m| json!({ "role": m.role, "content": m.content }))
        .collect();
    json!({ "model": model, "max_tokens": 4096, "messages": msgs })
}

pub fn parse_anthropic_reply(body: &Value) -> Result<String, String> {
    if let Some(msg) = body.get("error").and_then(|e| e.get("message")).and_then(|m| m.as_str()) {
        return Err(msg.to_string());
    }
    body.get("content")
        .and_then(|c| c.get(0))
        .and_then(|c0| c0.get("text"))
        .and_then(|t| t.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "unexpected response shape".to_string())
}

#[tauri::command]
pub async fn ai_chat(provider: String, model: String, messages: Vec<ChatMessage>) -> Result<String, String> {
    if provider != "anthropic" {
        return Err(format!("{} chat is not supported yet", provider));
    }
    let key = crate::fs_commands::read_provider_key(&provider)?;
    let body = build_anthropic_body(&model, &messages);
    let client = reqwest::Client::new();
    let resp = client
        .post("https://api.anthropic.com/v1/messages")
        .header("x-api-key", key)
        .header("anthropic-version", "2023-06-01")
        .header("content-type", "application/json")
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let json: Value = resp.json().await.map_err(|e| e.to_string())?;
    parse_anthropic_reply(&json)
}

#[cfg(test)]
mod tests {
    use super::{build_anthropic_body, parse_anthropic_reply, ChatMessage};
    use serde_json::json;

    #[test]
    fn body_has_model_max_tokens_and_messages() {
        let msgs = vec![ChatMessage { role: "user".into(), content: "hi".into() }];
        let b = build_anthropic_body("claude-sonnet-4-6", &msgs);
        assert_eq!(b["model"], "claude-sonnet-4-6");
        assert_eq!(b["max_tokens"], 4096);
        assert_eq!(b["messages"][0]["role"], "user");
        assert_eq!(b["messages"][0]["content"], "hi");
    }

    #[test]
    fn parse_reply_extracts_text() {
        let body = json!({ "content": [ { "type": "text", "text": "hello there" } ] });
        assert_eq!(parse_anthropic_reply(&body).unwrap(), "hello there");
    }

    #[test]
    fn parse_reply_surfaces_error_message() {
        let body = json!({ "type": "error", "error": { "type": "x", "message": "bad key" } });
        assert_eq!(parse_anthropic_reply(&body), Err("bad key".to_string()));
    }
}
