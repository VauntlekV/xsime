#include <chrono>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>

#include <fcitx-utils/capabilityflags.h>
#include <fcitx-utils/event.h>
#include <fcitx-utils/eventdispatcher.h>
#include <fcitx-utils/key.h>
#include <fcitx-utils/keysym.h>
#include <fcitx-utils/testing.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/inputmethodgroup.h>
#include <fcitx/inputmethodmanager.h>
#include <fcitx/instance.h>
#include <testfrontend_public.h>

namespace {

int g_exit_status = EXIT_SUCCESS;

struct TestFailed : std::runtime_error {
    explicit TestFailed(const std::string& message) : std::runtime_error(message) {}
};

void Die(const std::string& message) {
    std::cerr << "FAIL: " << message << '\n';
    g_exit_status = EXIT_FAILURE;
    throw TestFailed(message);
}

void SendKey(fcitx::AddonInstance* frontend, const fcitx::ICUUID& uuid, const char* name) {
    frontend->call<fcitx::ITestFrontend::keyEvent>(uuid, fcitx::Key(name), false);
    frontend->call<fcitx::ITestFrontend::keyEvent>(uuid, fcitx::Key(name), true);
}

std::string IsolateDirs(const std::string& stub_path) {
    const auto root = std::filesystem::temp_directory_path() /
                      ("rimes-buffer-respawn-" + std::to_string(getpid()));
    std::error_code error;
    std::filesystem::remove_all(root, error);
    std::filesystem::create_directories(root / "user" / "log", error);
    if (error) {
        Die("could not create isolated dirs: " + error.message());
    }
    static std::string user_env;
    static std::string log_env;
    static std::string socket_env;
    static std::string dump_env;
    static std::string ui_env;
    user_env = (root / "user").string();
    log_env = (root / "user" / "log").string();
    socket_env = (root / "rimes-buffer.sock").string();
    dump_env = (root / "buffer-snapshot.json").string();
    ui_env = stub_path;
    setenv("RIMES_USER_DIR", user_env.c_str(), 1);
    setenv("RIMES_LOG_DIR", log_env.c_str(), 1);
    setenv("RIMES_BUFFER_SOCKET", socket_env.c_str(), 1);
    setenv("RIMES_BUFFER_DUMP", dump_env.c_str(), 1);
    setenv("RIMES_BUFFER_UI", ui_env.c_str(), 1);
    setenv("RIMES_BUFFER_CONNECT_DELAY_MS", "1500", 1);
    unsetenv("RIMES_BUFFER_HEADLESS");
    setenv("RIMES_BUFFER_AUTO_CAPTURE", "0", 1);
    setenv("RIMES_BUFFER_CLOSE_AFTER_LAST", "1", 1);
    setenv("RIMES_BUFFER_FOCUS_GRACE_MS", "200", 1);
    return dump_env;
}

std::string ReadDump(const std::string& path) {
    std::ifstream in(path);
    if (!in) {
        Die("buffer dump is missing at " + path);
    }
    return std::string((std::istreambuf_iterator<char>(in)),
                       std::istreambuf_iterator<char>());
}

int UiClientCount(const std::string& dump_path) {
    const auto json = ReadDump(dump_path);
    const auto key = json.find("\"ui_clients\":");
    if (key == std::string::npos) {
        return -1;
    }
    return std::atoi(json.c_str() + key + std::strlen("\"ui_clients\":"));
}

int CountUiProcesses(const std::string& stub_path) {
    std::error_code canon_error;
    const auto wanted = std::filesystem::weakly_canonical(stub_path, canon_error);
    int count = 0;
    DIR* proc = opendir("/proc");
    if (proc == nullptr) {
        return -1;
    }
    while (dirent* entry = readdir(proc)) {
        if (entry->d_name[0] < '0' || entry->d_name[0] > '9') {
            continue;
        }
        const std::string exe = std::string("/proc/") + entry->d_name + "/exe";
        std::error_code error;
        const auto resolved = std::filesystem::weakly_canonical(exe, error);
        if (error) {
            continue;
        }
        if (resolved == wanted) {
            ++count;
        }
    }
    closedir(proc);
    return count;
}

void KillUiProcesses(const std::string& stub_path) {
    std::error_code canon_error;
    const auto wanted = std::filesystem::weakly_canonical(stub_path, canon_error);
    DIR* proc = opendir("/proc");
    if (proc == nullptr) {
        return;
    }
    while (dirent* entry = readdir(proc)) {
        if (entry->d_name[0] < '0' || entry->d_name[0] > '9') {
            continue;
        }
        const std::string exe = std::string("/proc/") + entry->d_name + "/exe";
        std::error_code error;
        const auto resolved = std::filesystem::weakly_canonical(exe, error);
        if (error || resolved != wanted) {
            continue;
        }
        const pid_t pid = static_cast<pid_t>(std::atoi(entry->d_name));
        if (pid > 0) {
            kill(pid, SIGKILL);
        }
    }
    closedir(proc);
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 4) {
        std::cerr << "Usage: rimes-buffer-respawn-e2e <build-dir> <addon-rel-dir> <data-rel-dir>\n";
        return EXIT_FAILURE;
    }

    try {
        const auto build_dir = std::filesystem::path(argv[1]);
        const auto stub_path = (build_dir / "rimes-buffer-ui-stub").string();
        if (access(stub_path.c_str(), X_OK) != 0) {
            std::cerr << "FAIL: missing UI stub at " << stub_path << '\n';
            return EXIT_FAILURE;
        }
        const auto dump_path = IsolateDirs(stub_path);
        fcitx::setupTestingEnvironment(argv[1], {argv[2]}, {argv[3]});

        char arg0[] = "rimes-buffer-respawn-e2e";
        char arg1[] = "--disable=all";
        char arg2[] = "--enable=testfrontend,testui,rimes";
        char* args[] = {arg0, arg1, arg2};
        fcitx::Instance instance(3, args);
        instance.addonManager().registerDefaultLoader(nullptr);

        fcitx::EventDispatcher dispatcher;
        dispatcher.attach(&instance.eventLoop());

        fcitx::AddonInstance* frontend = nullptr;
        fcitx::ICUUID uuid{};
        fcitx::InputContext* ic = nullptr;
        std::unique_ptr<fcitx::EventSourceTime> wait_timer;
        std::unique_ptr<fcitx::EventSourceTime> connected_timer;
        std::unique_ptr<fcitx::EventSourceTime> after_kill_timer;
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(180);
        bool suite_started = false;

        dispatcher.schedule([&]() {
            auto& manager = instance.inputMethodManager();
            if (manager.entry("rimes") == nullptr) {
                Die("input method 'rimes' was not registered");
            }
            if (manager.groupCount() == 0) {
                manager.addEmptyGroup("Default");
                manager.setGroupOrder({"Default"});
            }
            fcitx::InputMethodGroup group("Default");
            group.setDefaultLayout("us");
            group.inputMethodList().emplace_back(fcitx::InputMethodGroupItem("rimes"));
            group.setDefaultInputMethod("rimes");
            manager.setGroup(group);
            manager.setCurrentGroup("Default");

            frontend = instance.addonManager().addon("testfrontend", true);
            if (frontend == nullptr) {
                Die("testfrontend addon did not load");
            }
            uuid = frontend->call<fcitx::ITestFrontend::createInputContext>("rimes-buffer-respawn");
            ic = instance.inputContextManager().findByUUID(uuid);
            if (ic == nullptr) {
                Die("test input context was not created");
            }
            instance.setCurrentInputMethod(ic, "rimes", true);
            if (instance.inputMethod(ic) != "rimes") {
                Die("could not switch the test context to rimes");
            }

            wait_timer = instance.eventLoop().addTimeEvent(
                CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + 50000, 50000,
                [&](fcitx::EventSourceTime* source, uint64_t) {
                    if (std::chrono::steady_clock::now() > deadline) {
                        Die("addon stayed in Deploying; deploy-ready notify never ran");
                    }
                    auto* ime = instance.inputMethodEngine(ic);
                    const auto* entry = instance.inputMethodEntry(ic);
                    if (ime != nullptr && entry != nullptr &&
                        ime->subMode(*entry, *ic) == "Deploying") {
                        source->setTime(fcitx::now(CLOCK_MONOTONIC) + 200000);
                        source->setOneShot();
                        return true;
                    }
                    if (suite_started) {
                        return true;
                    }
                    suite_started = true;
                    ic->setCapabilityFlags(fcitx::CapabilityFlags{fcitx::CapabilityFlag::Preedit} |
                                           fcitx::CapabilityFlag::ClientUnfocusCommit);
                    SendKey(frontend, uuid, "Alt+Shift+B");
                    const auto opened = ReadDump(dump_path);
                    if (opened.find("\"visible\":true") == std::string::npos) {
                        Die("Alt+Shift+B did not show the workbench");
                    }
                    connected_timer = instance.eventLoop().addTimeEvent(
                        CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + 200000, 200000,
                        [&, stub_path](fcitx::EventSourceTime* poll, uint64_t) {
                            if (std::chrono::steady_clock::now() > deadline) {
                                Die("slow UI stub never connected");
                            }
                            if (UiClientCount(dump_path) < 1) {
                                poll->setTime(fcitx::now(CLOCK_MONOTONIC) + 200000);
                                poll->setOneShot();
                                return true;
                            }
                            if (CountUiProcesses(stub_path) != 1) {
                                Die("expected exactly one UI process before kill");
                            }
                            std::cout << "ok: first UI connected\n";
                            KillUiProcesses(stub_path);
                            after_kill_timer = instance.eventLoop().addTimeEvent(
                                CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + 2000000, 0,
                                [&, stub_path](fcitx::EventSourceTime*, uint64_t) {
                                    try {
                                        const int processes = CountUiProcesses(stub_path);
                                        const int clients = UiClientCount(dump_path);
                                        if (processes != 1) {
                                            Die("after kill+2s expected 1 UI process, got " +
                                                std::to_string(processes));
                                        }
                                        if (clients != 1) {
                                            Die("after kill+2s expected 1 UI client, got " +
                                                std::to_string(clients));
                                        }
                                        std::cout << "ok: UI respawn kept a single delayed client\n";
                                        frontend->call<fcitx::ITestFrontend::destroyInputContext>(
                                            uuid);
                                        instance.exit();
                                    } catch (const TestFailed&) {
                                        instance.exit();
                                    }
                                    return true;
                                });
                            return true;
                        });
                    return true;
                });
        });

        try {
            const int rc = instance.exec();
            KillUiProcesses(stub_path);
            return g_exit_status != EXIT_SUCCESS ? g_exit_status : rc;
        } catch (const fcitx::InstanceQuietQuit&) {
            KillUiProcesses(stub_path);
            return g_exit_status;
        }
    } catch (const TestFailed&) {
        return EXIT_FAILURE;
    } catch (const std::exception& exception) {
        std::cerr << "FAIL: " << exception.what() << '\n';
        return EXIT_FAILURE;
    }
}
