# 회원가입/로그인 관련 커스텀 예외 정의

class DuplicateEmailError(Exception): pass
class DuplicateUsernameError(Exception): pass
class InvalidPasswordError(Exception): pass
class UserNotFoundError(Exception): pass
