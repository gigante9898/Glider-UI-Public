# ⚡ Glider UI

A modern, responsive, and aesthetic UI library for Roblox Luau scripts.

[![Discord](https://img.shields.io/badge/Discord-Join%20Community-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/dJ5yNFZYmX)

---

## 🌐 Official Discord & Community

Join our Discord for script hub updates, releases, support, and custom commissions:

👉 **[https://discord.gg/dJ5yNFZYmX](https://discord.gg/dJ5yNFZYmX)**

- **Script Hub & Loader Releases**: Get the latest builds and updates.
- **Support & Bug Reports**: Direct assistance and active troubleshooting.
- **Custom Scripts & Commissions**: Custom automation and features starting at **+5 EUR** (DM `jirxy_2`).

---

## 🚀 Quick Start

```lua
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/gigante9898/Glider-UI-Public/main/UIAPI_Glider.lua?v=" .. tick()))()

local Window = Library.new({
    Title = "Glider UI",
    Folder = "GliderConfig"
})

local Tab = Window:AddTab("Main")
local Section = Tab:AddSection("Features")

Section:AddToggle({
    Title = "Enable Assist",
    Default = false,
    Flag = "EnableAssist",
    Callback = function(state)
        print("Toggled:", state)
    end
})

Window:AutoLoad()
```
