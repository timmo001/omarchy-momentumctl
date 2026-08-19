# Maintainer: Aidan Timson (Timmo) <aidan@timmo.dev>
pkgname=momentumctl
pkgver=0.1.0
pkgrel=1
pkgdesc="Control Sennheiser MOMENTUM 4 headphones"
arch=('x86_64')
url="https://github.com/gjabell/momentumctl"
license=('MIT')
options=('!debug')
depends=('dbus' 'gcc-libs' 'glibc')
makedepends=('cargo')
source=("$pkgname-$pkgver.tar.gz::https://github.com/gjabell/momentumctl/archive/e86f3e22a0278892c073d1a9f956e5976839c661.tar.gz")
sha256sums=('f1098f325eb1e832800b23aae4ab82799377ec1863c9bf06d8560f82c7bc1f56')

prepare() {
  cd "$pkgname-e86f3e22a0278892c073d1a9f956e5976839c661"
  export RUSTUP_TOOLCHAIN=stable
  cargo fetch --locked --target "$CARCH-unknown-linux-gnu"
}

build() {
  cd "$pkgname-e86f3e22a0278892c073d1a9f956e5976839c661"
  export RUSTUP_TOOLCHAIN=stable
  export CARGO_TARGET_DIR=target
  cargo build --frozen --release
}

check() {
  cd "$pkgname-e86f3e22a0278892c073d1a9f956e5976839c661"
  export RUSTUP_TOOLCHAIN=stable
  export CARGO_TARGET_DIR=target
  cargo test --frozen
}

package() {
  cd "$pkgname-e86f3e22a0278892c073d1a9f956e5976839c661"
  install -Dm755 target/release/momentumctl "$pkgdir/usr/bin/momentumctl"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
