#pragma once
#include "ContainerABI.hpp"
#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>

namespace Hyprflip::FloatingCards {
inline constexpr uint64_t EPOCH = 0x484650464c4f4154ULL;
const ContainerAPI *api();
uint64_t create(const ContainerSnapshot &snapshot);
bool canCreate(const ContainerSnapshot &snapshot);
void closing(PHLWINDOW window);
void focused(PHLWINDOW window);
// Installs the group-position hook floating cards depend on. Without it the
// module refuses cards and the rest of Hyprflip keeps working.
bool start(HANDLE handle);
bool available();
void shutdown(HANDLE handle);
bool toggle(uint64_t id);
} // namespace Hyprflip::FloatingCards
