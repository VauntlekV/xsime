# Fedora package for the XSIME Fcitx5 input method.
#
# Builds against the distro librime/librime-lua instead of the private pinned
# runtime bundled in the Debian package. All network inputs are declared as
# Sources so the build works offline (mock / COPR).

# Override with: rpmbuild --define 'forgeowner X' --define 'commit SHA' --define 'commitdate YYYYMMDD'
%{!?forgeowner:%global forgeowner VauntlekV}
%{!?commit:%global commit c3d5e1a1c7a9f9a3c36885d03c0408952c323b50}
%{!?commitdate:%global commitdate 20261027}
%global shortcommit  %(c=%{commit}; echo ${c:0:7})
%global _vpath_srcdir platforms/linux/ime
# Upstream generates some sources from several rules, which Ninja rejects.
%global _cmake_generator "Unix Makefiles"

# Pinned in plugins.lock.json and the OfficialPlugins gitlink.
%global plugins_commit 8709e06d229b28d63ba068abb391aac22a7f380a
# Pinned in Shared/SchemeImport/CMakeLists.txt (FetchContent).
%global yaml_commit    f7320141120f720aecc4c32be25586e7da9eb978
%global miniz_commit   77d0dce8627735138c51770d1799a1ef48f2117d
%global picosha_commit 161cb3fc4170fa7a3eca9e582cebd27cc4d1fe29

Name:           fcitx5-rimes
Version:        1.2.0
Release:        0.1.%{commitdate}git%{shortcommit}%{?dist}
Summary:        XSIME input method frontend for Fcitx 5

# Project: MIT. Bundled static deps: yaml-cpp (MIT), miniz (MIT), PicoSHA2 (MIT).
# Rime data and plugins carry their own notices under /usr/share/licenses/rimes.
License:        MIT AND Apache-2.0 AND BSD-3-Clause
URL:            https://github.com/scholay/xsime
Source0:        https://github.com/%{forgeowner}/xsime/archive/%{commit}/xsime-%{shortcommit}.tar.gz
Source1:        https://github.com/scholay/rimes-plugins/archive/%{plugins_commit}/rimes-plugins-%{plugins_commit}.tar.gz
Source2:        https://github.com/jbeder/yaml-cpp/archive/%{yaml_commit}/yaml-cpp-%{yaml_commit}.tar.gz
Source3:        https://github.com/richgel999/miniz/archive/%{miniz_commit}/miniz-%{miniz_commit}.tar.gz
Source4:        https://github.com/okdshin/PicoSHA2/archive/%{picosha_commit}/PicoSHA2-%{picosha_commit}.tar.gz

BuildRequires:  cmake
BuildRequires:  extra-cmake-modules
BuildRequires:  gcc-c++
BuildRequires:  gettext
BuildRequires:  pkgconfig
BuildRequires:  python3
BuildRequires:  fcitx5-devel
BuildRequires:  openssl-devel
BuildRequires:  sqlite-devel
BuildRequires:  pkgconfig(rime) >= 1.7.0
BuildRequires:  pkgconfig(gtk+-3.0)
BuildRequires:  pkgconfig(gtk-layer-shell-0)
BuildRequires:  pkgconfig(vte-2.91) >= 0.76
BuildRequires:  pkgconfig(icu-i18n)
BuildRequires:  pkgconfig(icu-uc)
BuildRequires:  pkgconfig(poppler-glib)
BuildRequires:  pkgconfig(gstreamer-1.0)
BuildRequires:  pkgconfig(gstreamer-app-1.0)
BuildRequires:  pkgconfig(gstreamer-video-1.0)
BuildRequires:  pkgconfig(libportal)
BuildRequires:  pkgconfig(gio-unix-2.0)
BuildRequires:  pkgconfig(x11)
BuildRequires:  pkgconfig(xcb)
BuildRequires:  pkgconfig(xcb-xfixes)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(libcurl)

Requires:       fcitx5
Requires:       hicolor-icon-theme
# The schemes use Lua processors/filters; librime loads the plugin at runtime.
Requires:       librime-lua%{?_isa}
# opencc/s2t.json and its dictionaries are an external runtime dependency.
Requires:       opencc
Requires:       python3
Requires:       polkit
Requires:       gstreamer1-plugins-base
Requires:       gstreamer1-plugins-good
Requires:       pipewire-gstreamer
Requires:       xdg-desktop-portal
Recommends:     fcitx5-gtk
Recommends:     xdg-desktop-portal-gtk
Recommends:     wl-clipboard
Recommends:     google-noto-sans-cjk-fonts
Recommends:     google-noto-color-emoji-fonts
Recommends:     rsms-inter-fonts

%description
XSIME is a librime frontend for Fcitx 5. It deploys the reviewed XSIME
rime-data set, keeps user state in ~/.local/share/rimes (isolated from
fcitx5-rime), and ships the Buffer workbench, Capsule rail, Mailbox
workspace and scheme importer next to the Fcitx5 addon.

This build uses the system librime and librime-lua.


%prep
%autosetup -n xsime-%{commit} -p1
mkdir -p OfficialPlugins
tar -xzf %{SOURCE1} -C OfficialPlugins --strip-components=1
mkdir -p %{_builddir}/deps/{yaml,miniz,picosha}
tar -xzf %{SOURCE2} -C %{_builddir}/deps/yaml    --strip-components=1
tar -xzf %{SOURCE3} -C %{_builddir}/deps/miniz   --strip-components=1
tar -xzf %{SOURCE4} -C %{_builddir}/deps/picosha --strip-components=1
# Newer distro compilers add warnings upstream's CI toolchain does not see.
find platforms/linux Shared -name CMakeLists.txt -exec \
    sed -i -e 's/ -Werror)/)/' -e '/^ *-Werror$/d' {} +


%build
export RIMES_OFFICIAL_PLUGINS_REVISION=%{plugins_commit}
%cmake \
    -DBUILD_SHARED_LIBS=OFF \
    -DRIMES_BUILD_FCITX5=ON \
    -DRIMES_BUILD_TESTS=OFF \
    -DRIMES_BUILD_QT_HOST=OFF \
    -DRIMES_PRODUCT_VERSION=%{version} \
    -DFCITX_INSTALL_USE_FCITX_SYS_PATHS=ON \
    -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
    -DFETCHCONTENT_SOURCE_DIR_RIMES_YAML=%{_builddir}/deps/yaml \
    -DFETCHCONTENT_SOURCE_DIR_RIMES_MINIZ=%{_builddir}/deps/miniz \
    -DFETCHCONTENT_SOURCE_DIR_RIMES_SHA=%{_builddir}/deps/picosha \
    -Wno-dev
%cmake_build


%install
%cmake_install
python3 platforms/linux/ime/scripts/stage-data.py \
    --repo-root . \
    --output-dir %{buildroot}%{_datadir}/rimes/data
install -Dpm 0644 platforms/linux/ime/README.md %{buildroot}%{_docdir}/%{name}/README.md


%files
%license LICENSE NOTICE LICENSING.md ATTRIBUTION.md THIRD_PARTY_NOTICES.md
%doc %{_docdir}/%{name}/README.md
%{_bindir}/rimes-*
%{_libdir}/fcitx5/rimes.so
%{_libexecdir}/rimes/
%{_datadir}/applications/org.scholay.rimes.*.desktop
%{_datadir}/fcitx5/addon/rimes.conf
%{_datadir}/fcitx5/inputmethod/rimes.conf
%{_datadir}/icons/hicolor/*/apps/rimes.png
%{_datadir}/licenses/rimes/
%{_metainfodir}/org.fcitx.Fcitx5.Addon.Rimes.metainfo.xml
%{_datadir}/rimes/


%changelog
* Tue Oct 27 2026 XSIME Fedora packaging <noreply@github.com> - 1.2.0-0.1
- Initial Fedora package built against system librime
