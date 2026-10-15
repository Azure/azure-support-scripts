use leptos::prelude::*;

/// Three-way theme toggle: Dark → Light → Colorblind → Dark …
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Theme {
    Dark,
    Light,
    Colorblind,
}

impl Theme {
    pub fn class_name(self) -> &'static str {
        match self {
            Self::Dark => "dark-mode",
            Self::Light => "",
            Self::Colorblind => "colorblind-mode",
        }
    }

    pub fn icon(self) -> &'static str {
        match self {
            Self::Dark => "DARK",
            Self::Light => "LIGHT",
            Self::Colorblind => "CB",
        }
    }

    pub fn cycle(self) -> Self {
        match self {
            Self::Dark => Self::Colorblind,
            Self::Colorblind => Self::Light,
            Self::Light => Self::Dark,
        }
    }

    /// Read from `localStorage`, falling back to `Dark`.
    pub fn from_storage() -> Self {
        let window = web_sys::window().unwrap();
        let storage = window.local_storage().ok().flatten();
        match storage.and_then(|s| s.get_item("theme").ok().flatten()) {
            Some(ref v) if v.is_empty() => Self::Light,
            Some(ref v) if v == "colorblind-mode" => Self::Colorblind,
            _ => Self::Dark,
        }
    }

    /// Persist to `localStorage`.
    pub fn save(self) {
        let window = web_sys::window().unwrap();
        if let Ok(Some(storage)) = window.local_storage() {
            let _ = storage.set_item("theme", self.class_name());
        }
    }
}

#[component]
pub fn ThemeToggle(theme: ReadSignal<Theme>, set_theme: WriteSignal<Theme>) -> impl IntoView {
    let toggle = move |_| {
        let next = theme.get().cycle();
        next.save();
        set_theme.set(next);
    };

    let aria_label = move || match theme.get() {
        Theme::Dark => "Switch to color-blind friendly mode",
        Theme::Colorblind => "Switch to light mode",
        Theme::Light => "Switch to dark mode",
    };

    view! {
        <button
            id="theme-toggle"
            class="theme-toggle"
            on:click=toggle
            title="Toggle theme"
            aria-label=aria_label
        >
            <span id="theme-icon">{move || theme.get().icon()}</span>
        </button>
    }
}
