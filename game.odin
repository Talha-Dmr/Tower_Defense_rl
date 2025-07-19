package main

import "core:fmt"
import rl "vendor:raylib"
import "core:math"

// Constants
GRID_SIZE :: 96
GRID_COLS :: 10
GRID_ROWS :: 5
UI_POS :: rl.Vector2{50, 50}
UI_POS_STRAIGHT :: rl.Vector2{50, 50}
UI_POS_ARCED :: rl.Vector2{50, 120}
UI_TOWER_SIZE :: 50

// Assets
Textures :: struct {
    floor, tower, projectile : rl.Texture2D,
}

TowerType :: enum {
    STRAIGHT_SHOOTER,  // Sağa düz atış
    ARCED_SHOOTER,     // Eğik atış
}

// Her kule tipi için UI pozisyonlarını saklayan yapı
TowerUIPositions :: struct {
    straight_shooter: rl.Vector2,
    arced_shooter: rl.Vector2,
}

// Global olarak tanımla
tower_ui_positions := TowerUIPositions{
    straight_shooter = {50, 50},   // Düz atış kulesi UI pozisyonu
    arced_shooter    = {50, 120},  // Eğik atış kulesi UI pozisyonu (altında)
}

Tower :: struct {
    pos: rl.Vector2,
    tex: ^rl.Texture2D,
    type: TowerType,    // Kule tipi
    last_shot: f32,
    cooldown: f32,
    projectiles: [dynamic]Projectile,
}

Projectile :: struct {
    pos: rl.Vector2,
    vel: rl.Vector2,
    gravity: f32,  // Yerçekimi etkisi
    lifetime: f32, // Mermi ömrü
}

Level :: struct {
    floors: [dynamic]rl.Vector2,
    towers: [dynamic]Tower,
}

// Vector2 normalize fonksiyonu (Raylib'de built-in olmadığı için)
vector2_normalize :: proc(v: rl.Vector2) -> rl.Vector2 {
    length := math.sqrt(v.x*v.x + v.y*v.y)
    if length > 0 {
        return {v.x/length, v.y/length}
    }
    return {0, 0}
}

Game :: struct {
    camera: rl.Camera2D,
    tex: Textures,
    level: Level,
    ui: struct {
        tower_pos: rl.Vector2,
        dragging: bool,
        selected_type: TowerType,
    },
    edit_mode: bool,  // Eklendi
    time: f32,        // Eklendi
    projectiles: [dynamic]Projectile,  // Eklendi
    is_paused: bool,
    pause_time: f32,
}

game: Game

init :: proc() {
    rl.InitWindow(1080, 720, "Tower Defense")
    rl.SetTargetFPS(240)
    
    game.tex.projectile = rl.LoadTexture("soil.png") // Mermi texture'ı
    game.tex.floor = rl.LoadTexture("floor.png")
    game.tex.tower = rl.LoadTexture("pea.png")

    if game.tex.projectile.id != 0 {
    fmt.println("Mermi texture yüklendi, boyut:", game.tex.projectile.width, "x", game.tex.projectile.height)
    }

    game.camera = {
        target = {f32(GRID_COLS * GRID_SIZE) / 2, f32(GRID_ROWS * GRID_SIZE) / 2},
        offset = {f32(rl.GetScreenWidth()) / 2, f32(rl.GetScreenHeight()) / 2},
        zoom = 1.0,
    }
    
    game.ui.tower_pos = UI_POS
    game.ui.selected_type = .STRAIGHT_SHOOTER
}

cleanup :: proc() {
    rl.UnloadTexture(game.tex.floor)
    rl.UnloadTexture(game.tex.tower)
    rl.UnloadTexture(game.tex.projectile)
    
    // Tüm kulelerin mermilerini temizle
    for &tower in game.level.towers {
        delete(tower.projectiles)
    }
    
    // Global mermileri temizle
    delete(game.projectiles)
    
    delete(game.level.floors)
    delete(game.level.towers)
    rl.CloseWindow()
}

snap_to_grid :: proc(pos: rl.Vector2) -> rl.Vector2 {
    return {
        f32(i32(pos.x / GRID_SIZE)) * GRID_SIZE,
        f32(i32(pos.y / GRID_SIZE)) * GRID_SIZE,
    }
}

is_valid_spot :: proc(pos: rl.Vector2) -> bool {
    snapped := snap_to_grid(pos)
    for &floor in game.level.floors {
        if floor == snapped do return true
    }
    return false
}

handle_input :: proc() {
    // Kamera hareketi (WASD veya ok tuşları)
    handle_camera_movement :: proc() {
        // Boolean'ı f32'ye dönüştürmek için ternary operator kullanıyoruz
        right := f32(rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) ? 1 : 0)
        left := f32(rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) ? 1 : 0)
        down := f32(rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) ? 1 : 0)
        up := f32(rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) ? 1 : 0)
        
        move := rl.Vector2{right - left, down - up}
        game.camera.target += move * 5.0
    }

    // Kule seçim işlemleri
    handle_tower_selection :: proc() {
        mouse := rl.GetMousePosition()
        world_pos := rl.GetScreenToWorld2D(mouse, game.camera)
        
        // 1-2 tuşlarıyla kule seçimi
        if rl.IsKeyPressed(.ONE) {
            game.ui.selected_type = .STRAIGHT_SHOOTER
            game.ui.tower_pos = UI_POS_STRAIGHT
        }
        if rl.IsKeyPressed(.TWO) {
            game.ui.selected_type = .ARCED_SHOOTER
            game.ui.tower_pos = UI_POS_ARCED
        }

        // UI'dan kule sürükleme başlatma
        if !game.ui.dragging && rl.IsMouseButtonPressed(.LEFT) {
            straight_rect := rl.Rectangle{UI_POS_STRAIGHT.x, UI_POS_STRAIGHT.y, UI_TOWER_SIZE, UI_TOWER_SIZE}
            arced_rect := rl.Rectangle{UI_POS_ARCED.x, UI_POS_ARCED.y, UI_TOWER_SIZE, UI_TOWER_SIZE}
            
            if rl.CheckCollisionPointRec(mouse, straight_rect) {
                game.ui.dragging = true
                game.ui.selected_type = .STRAIGHT_SHOOTER
            } else if rl.CheckCollisionPointRec(mouse, arced_rect) {
                game.ui.dragging = true
                game.ui.selected_type = .ARCED_SHOOTER
            } else if is_valid_spot(world_pos) {
                // Direkt tıklama ile kule yerleştirme
                append(&game.level.towers, Tower{
                    pos = snap_to_grid(world_pos),
                    tex = &game.tex.tower,
                    type = game.ui.selected_type,
                    last_shot = game.time,
                    cooldown = 1.0,
                    projectiles = make([dynamic]Projectile),
                })
            }
        }

        // Sürükleme işlemi
        if game.ui.dragging {
            game.ui.tower_pos = mouse - {UI_TOWER_SIZE/2, UI_TOWER_SIZE/2}
            
            if rl.IsMouseButtonReleased(.LEFT) {
                game.ui.dragging = false
                if is_valid_spot(world_pos) {
                    append(&game.level.towers, Tower{
                        pos = snap_to_grid(world_pos),
                        tex = &game.tex.tower,
                        type = game.ui.selected_type,
                        last_shot = game.time,
                        cooldown = 1.0,
                        projectiles = make([dynamic]Projectile),
                    })
                }
                // UI pozisyonunu resetle
                game.ui.tower_pos = game.ui.selected_type == .STRAIGHT_SHOOTER ? UI_POS_STRAIGHT : UI_POS_ARCED
            }
        }
    }

    // Oyun durdurma/başlatma
    handle_pause :: proc() {
        if rl.IsKeyPressed(.P) {
            game.is_paused = !game.is_paused
            if game.is_paused {
                game.pause_time = 0
                fmt.println("Oyun duraklatıldı")
            } else {
                game.time += game.pause_time
                fmt.println("Oyun devam ediyor")
            }
        }
        if game.is_paused {
            game.pause_time += rl.GetFrameTime()
            return
        }
    }

    // Edit modu kontrolü
    handle_edit_mode :: proc() {
        if rl.IsKeyPressed(.F2) {
            game.edit_mode = !game.edit_mode
            fmt.println("Edit modu:", game.edit_mode ? "Açık" : "Kapalı")
        }
    }

    // Tüm input işlemlerini yönet
    handle_camera_movement()
    handle_pause()
    if !game.is_paused {
        handle_tower_selection()
        handle_edit_mode()
    }
}


edit_level :: proc() {
    mouse := rl.GetScreenToWorld2D(rl.GetMousePosition(), game.camera)
    grid_pos := snap_to_grid(mouse)
    
    if rl.IsMouseButtonPressed(.LEFT) {
        append(&game.level.floors, grid_pos)
    }
    if rl.IsMouseButtonPressed(.RIGHT) {
        for floor, i in game.level.floors {
            if floor == grid_pos {
                unordered_remove(&game.level.floors, i)
                break
            }
        }
    }
}

draw_grid :: proc() {
    for col in 0..<GRID_COLS {
        for row in 0..<GRID_ROWS {
            x := i32(col * GRID_SIZE)
            y := i32(row * GRID_SIZE)
            rl.DrawRectangleLines(x, y, GRID_SIZE, GRID_SIZE, rl.LIGHTGRAY)
        }
    }
}

draw_level :: proc() {
    // Zeminleri çiz
    for &floor in game.level.floors {
        rl.DrawTextureEx(game.tex.floor, floor, 0, 0.16, rl.WHITE)
    }
    
    // Kuleleri ve mermileri çiz
    for &tower in game.level.towers {
        // 1. Önce kuleyi çiz
        rl.DrawTextureEx(tower.tex^, tower.pos, 0, 0.08, rl.WHITE)
        
        // 2. Sonra bu kuleye ait mermileri çiz
        for &proj in tower.projectiles {
            // Texture boyutuna göre otomatik merkezleme
            proj_offset := rl.Vector2{
                f32(game.tex.projectile.width) * 0.05 / 2,
                f32(game.tex.projectile.height) * 0.05 / 2
            }
            
            rl.DrawTextureEx(
                game.tex.projectile,
                proj.pos - proj_offset, // Tam merkezleme
                0,
                0.05, // Ölçek
                rl.WHITE
            )
            
            // Debug için mermi pozisyonunu göster (isteğe bağlı)
            // rl.DrawCircle(i32(proj.pos.x), i32(proj.pos.y), 5, rl.RED)
        }
    }
}

draw_ui :: proc() {
    // Kule seçim butonları (cstring kullanarak)
    draw_tower_button :: proc(pos: rl.Vector2, text: cstring, is_selected: bool) {
        color := is_selected ? rl.YELLOW : rl.WHITE
        rl.DrawTextureEx(
            game.tex.tower,
            pos,
            0,
            0.05,
            color
        )
        rl.DrawText(
            text,
            i32(pos.x + UI_TOWER_SIZE + 10),
            i32(pos.y + UI_TOWER_SIZE/2 - 10),
            20,
            color
        )
    }

    // 1. Kule butonlarını çiz (artık cstring kullanıyoruz)
    draw_tower_button(UI_POS_STRAIGHT, "Duz Atis (1)", game.ui.selected_type == .STRAIGHT_SHOOTER && !game.ui.dragging)
    draw_tower_button(UI_POS_ARCED, "Egik Atis (2)", game.ui.selected_type == .ARCED_SHOOTER && !game.ui.dragging)

    // 2. Sürükleme animasyonu
    if game.ui.dragging {
        rl.DrawTextureEx(
            game.tex.tower,
            game.ui.tower_pos,
            0,
            0.05,
            rl.Fade(rl.WHITE, 0.7)
        )
    }

    // 3. Seçili kule bilgisi (cstring dönüşümü)
    selected_label: cstring = "Secili: "
    selected_value: cstring
    switch game.ui.selected_type {
        case .STRAIGHT_SHOOTER:
            selected_value = "Duz Atis Kulesi"
        case .ARCED_SHOOTER:
            selected_value = "Egik Atis Kulesi"
    }
    
    // Metin genişliği hesaplama
    selected_width := rl.MeasureText(selected_label, 20)
    
    // Bilgi yazısı
    rl.DrawText(selected_label, 20, 20, 20, rl.WHITE)
    rl.DrawText(selected_value, 20 + i32(selected_width), 20, 20, rl.YELLOW)

    // 4. Edit modu göstergesi
    if game.edit_mode {
        rl.DrawText(
            "EDIT MODE (F2 ile cikis)",
            rl.GetScreenWidth() - 200,
            20,
            20,
            rl.RED
        )
    }

    // 5. Pause durumu
    if game.is_paused {
        rl.DrawText(
            "PAUSED (P ile devam)",
            rl.GetScreenWidth()/2 - 100,
            50,
            30,
            rl.YELLOW
        )
    }
}

shoot_projectiles :: proc() {
    // Only update when not paused
    if game.is_paused do return
    
    delta_time := rl.GetFrameTime()
    game.time += delta_time
    
    for &tower in game.level.towers {
        if game.time - tower.last_shot >= tower.cooldown {
            switch tower.type {
                case .STRAIGHT_SHOOTER:
                    append(&tower.projectiles, Projectile{
                        pos = tower.pos + {GRID_SIZE/2, GRID_SIZE/2},
                        vel = {500.0, 0},
                        gravity = 0,
                        lifetime = 2.0
                    })
                
                case .ARCED_SHOOTER:
                    angle: f32 = 45.0 * math.PI / 180.0  // 45 degrees in radians
                    speed: f32 = 400.0
                    
                    // Calculate direction using proper trigonometry
                    direction := rl.Vector2{
                        math.cos(angle),
                        -math.sin(angle)  // Negative because y increases downward
                    }
                    
                    append(&tower.projectiles, Projectile{
                        pos = tower.pos + {GRID_SIZE/2, GRID_SIZE/2},
                        vel = {
                            direction.x * speed,
                            direction.y * speed
                        },
                        gravity = 400.0,
                        lifetime = 3.0
                    })
            }
            
            tower.last_shot = game.time
        }
    }
}

update_projectiles :: proc() {
    delta_time := rl.GetFrameTime()
    
    for &tower in game.level.towers {
        // Filtreleme işlemi
        filtered := make([dynamic]Projectile, 0, len(tower.projectiles))
        
        for proj in tower.projectiles {
            mut_proj := proj  // Yerel kopya
            
            // Eğik atış kulesi için yerçekimi
            if tower.type == .ARCED_SHOOTER {
                mut_proj.vel.y += mut_proj.gravity * delta_time
            }
            
            // Pozisyon güncelleme
            mut_proj.pos += mut_proj.vel * delta_time
            mut_proj.lifetime -= delta_time
            
            // Mermi hala geçerli mi?
            if mut_proj.lifetime > 0 && 
               mut_proj.pos.x > 0 && 
               mut_proj.pos.x < f32(rl.GetScreenWidth()) && 
               mut_proj.pos.y < f32(rl.GetScreenHeight()) {
                append(&filtered, mut_proj)
            }
        }
        
        // Eski diziyi temizle ve filtrelenmiş olanı ata
        delete(tower.projectiles)
        tower.projectiles = filtered
    }
}

draw_centered_text :: proc(text: cstring, y: f32, size: i32, color: rl.Color) {
    width := rl.MeasureText(text, size)
    rl.DrawText(text, (rl.GetScreenWidth()-width)/2, i32(y), size, color)
}

draw_pause_overlay :: proc() {
    rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), {0,0,0,180})
    draw_centered_text("GAME PAUSED", f32(rl.GetScreenHeight())/2-30, 60, rl.WHITE)
    draw_centered_text("Press P to continue", f32(rl.GetScreenHeight())/2+40, 20, rl.LIGHTGRAY)
}

main :: proc() {
    init()
    defer cleanup()
    
    for !rl.WindowShouldClose() {
        // Input
        handle_input()

        delta_time := rl.GetFrameTime()

        if game.is_paused {
            game.pause_time += delta_time
        } else {
            // Only update game logic when not paused
            game.time += delta_time
            if game.edit_mode do edit_level()
            shoot_projectiles()
            update_projectiles()
        }
        
        // Draw
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLUE)
        
        rl.BeginMode2D(game.camera)
        draw_level()
        if game.edit_mode do draw_grid()
        rl.EndMode2D()
        
        draw_ui()
        if game.is_paused do draw_pause_overlay()
        rl.EndDrawing()
    }
}