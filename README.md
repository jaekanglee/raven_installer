# Raven Installer

이 저장소는 Raven 본체와 분리된 설치 전용 bootstrap입니다.

## 용도

- 공개 배포용 설치 진입점
- 운영체제별 설치 감지
- 실제 Raven 앱 레포를 받아 `~/.Raven`에 설치

## 사용법

```bash
git clone <installer-repo> RavenInstaller
cd RavenInstaller
RAVEN_APP_REPO_URL=<app-repo-url> ./install.sh --setup
```

## 환경 변수

- `RAVEN_APP_REPO_URL`: 실제 Raven 앱 레포 URL
- `RAVEN_APP_BRANCH`: 기본 브랜치, 기본값 `main`
- `RAVEN_HOME`: 설치 대상 경로, 기본값 `~/.Raven`
- `RAVEN_APP_DIR`: 앱 소스 체크아웃 경로, 기본값 `~/.Raven`

## 동작

- macOS, Linux, WSL을 `uname`으로 판별합니다.
- 앱 레포를 체크아웃한 뒤, 그 레포의 `install.sh`를 실행합니다.
- 이 저장소는 개인화된 런타임 데이터나 사용자 설정을 포함하지 않습니다.
