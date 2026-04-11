# Raven Installer

이 저장소는 Raven Core와 분리된 설치 전용 bootstrap입니다.

## 용도

- 공개 배포용 설치 진입점
- 운영체제별 설치 감지
- `raven_installer` release asset으로 배포된 Raven Core 패키지를 받아 `~/.Raven`에 설치

## 사용법

원라인 설치:

```bash
curl -fsSL https://raw.githubusercontent.com/jaekanglee/raven_installer/main/install.sh | bash
```

setup까지 같이:

```bash
curl -fsSL https://raw.githubusercontent.com/jaekanglee/raven_installer/main/install.sh | bash -s -- --setup
```

주의:
- `curl | bash`처럼 non-interactive 파이프 설치에서는 `--setup`이 자동으로 skip될 수 있습니다.
- 이 경우 설치 후 터미널에서 `raven setup`을 따로 실행하면 됩니다.
- installer는 `~/.local/bin`을 셸 startup 파일(`~/.profile`, `~/.bashrc`, `~/.zshrc`)에 자동 반영합니다. 보통 새 셸을 열면 바로 `raven` 명령을 사용할 수 있습니다.
- 제거가 필요하면 `./install.sh --uninstall`으로 런처, PATH 보정, 앱 디렉터리, portable bootstrap을 정리할 수 있습니다.

격리 테스트:

```bash
curl -fsSL https://raw.githubusercontent.com/jaekanglee/raven_installer/main/install.sh | \
  RAVEN_HOME=/tmp/raven-test-home RAVEN_APP_DIR=/tmp/raven-test-home bash
```

또는 레포를 받아서 실행:

```bash
git clone <installer-repo> RavenInstaller
cd RavenInstaller
./install.sh --setup
```

기본값은 `jaekanglee/raven_installer`의 최신 published release tag 기준 release asset 입니다.
`RAVEN_RELEASE_TAG`/`RAVEN_RELEASE_ASSET_NAME`를 지정하면 특정 버전으로 고정 설치할 수 있습니다.

개발용으로 git 소스 설치도 가능합니다.

```bash
RAVEN_INSTALL_SOURCE=git \
RAVEN_APP_REPO_URL=<core-repo-url> \
./install.sh --setup
```

## 환경 변수

- `RAVEN_INSTALL_SOURCE`: `release` 또는 `git`, 기본값 `release`
- `RAVEN_RELEASE_REPO`: release 대상 GitHub repo, 기본값 `jaekanglee/raven_installer`
- `RAVEN_RELEASE_TAG`: 설치할 release tag (미지정 시 최신 published release tag 자동 조회)
- `RAVEN_RELEASE_ASSET_NAME`: 다운로드할 asset 이름 (미지정 시 선택된 tag 기준으로 자동 결정)
- `RAVEN_APP_REPO_URL`: git 소스 설치용 앱 레포 URL
- `RAVEN_APP_BRANCH`: git 소스 설치용 브랜치, 기본값 `main`
- `RAVEN_HOME`: 설치 대상 경로, 기본값 `~/.Raven`
- `RAVEN_APP_DIR`: 앱 소스 체크아웃 경로, 기본값 `~/.Raven`

## 동작

- macOS, Linux, WSL을 `uname`으로 판별합니다.
- `node`/`npm`이 없으면 macOS/Linux에서 공식 Node 배포본을 사용자 홈 아래 bootstrap 디렉터리에 내려받아 사용합니다.
- 기본 bootstrap 경로는 `~/.local/share/raven/bootstrap`이며, `RAVEN_NODE_VERSION`/`RAVEN_BOOTSTRAP_DIR`로 조정할 수 있습니다.
- 기본값은 portable Node를 우선 사용하며, 시스템 Node를 강제하려면 `RAVEN_USE_SYSTEM_NODE=1`을 지정합니다.
- 기본적으로 public GitHub release feed에서 최신 published release tag를 고른 뒤, 해당 release asset을 내려받아 그 안의 `install.sh`를 실행합니다.
- 설치 후 `~/.local/bin/raven` 런처가 생성되고, installer가 PATH 자동 반영까지 수행합니다.
- 필요하면 git clone 방식으로도 설치할 수 있습니다.
- 이 저장소는 개인화된 런타임 데이터나 사용자 설정을 포함하지 않습니다.

설치가 완료되면 인그레스 보안 환경변수 템플릿이 기본 경로(`$HOME/.Raven/ingress-env.template.sh`)에 생성됩니다.

경로를 바꾸려면 설치 전에 다음을 지정하세요.

```bash
RAVEN_ENV_TEMPLATE_OUT="$HOME/.Raven/custom-ingress-env.sh" \
  ./install.sh
```
