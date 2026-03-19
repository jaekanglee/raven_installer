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

기본값은 `jaekanglee/raven_installer`의 `v1.0.2` release asset `raven_core-v1.0.2.tar.gz` 입니다.

개발용으로 git 소스 설치도 가능합니다.

```bash
RAVEN_INSTALL_SOURCE=git \
RAVEN_APP_REPO_URL=<core-repo-url> \
./install.sh --setup
```

## 환경 변수

- `RAVEN_INSTALL_SOURCE`: `release` 또는 `git`, 기본값 `release`
- `RAVEN_RELEASE_REPO`: release 대상 GitHub repo, 기본값 `jaekanglee/raven_installer`
- `RAVEN_RELEASE_TAG`: 설치할 release tag, 기본값 `v1.0.2`
- `RAVEN_RELEASE_ASSET_NAME`: 다운로드할 asset 이름, 기본값 `raven_core-v1.0.2.tar.gz`
- `RAVEN_APP_REPO_URL`: git 소스 설치용 앱 레포 URL
- `RAVEN_APP_BRANCH`: git 소스 설치용 브랜치, 기본값 `main`
- `RAVEN_HOME`: 설치 대상 경로, 기본값 `~/.Raven`
- `RAVEN_APP_DIR`: 앱 소스 체크아웃 경로, 기본값 `~/.Raven`

## 동작

- macOS, Linux, WSL을 `uname`으로 판별합니다.
- 기본적으로 public GitHub release asset을 내려받은 뒤, 그 안의 `install.sh`를 실행합니다.
- 필요하면 git clone 방식으로도 설치할 수 있습니다.
- 이 저장소는 개인화된 런타임 데이터나 사용자 설정을 포함하지 않습니다.
