require "./helper"

module ACAEngine::Model
  # Sample data
  USER_META = UserJWT::Metadata.new(
    name: "abcde",
    email: "abcde@protonmail.com",
    permissions: UserJWT::Permissions::AdminSupport,
  )

  ATTRIBUTES = {
    iss:  "ACAE",
    iat:  Time.unix(1000),
    exp:  Time.unix(Int32::MAX),
    aud:  "protonmail.com",
    sub:  "1234",
    user: USER_META,
  }

  ALGORITHM = JWT::Algorithm::RS256
  KEY       = <<-KEY
  -----BEGIN RSA PRIVATE KEY-----
  MIIEpAIBAAKCAQEAt01C9NBQrA6Y7wyIZtsyur191SwSL3MjR58RIjZ5SEbSyzMG
  3r9v12qka4UtpB2FmON2vwn0fl/7i3Jgh1Xth/s+TqgYXMebdd123wodrbex5pi3
  Q7PbQFT6hhNpnsjBh9SubTf+IeTIFeXUyqtqcDBmEoT5GxU6O+Wuch2GtbfEAmaD
  roy+uyB7P5DxpKLEx8nlVYgpx5g2mx2LufHvykVnx4bFzLezU93SIEW6yjPwUmv9
  R+wDM/AOg60dIf3hCh1DO+h22aKT8D8ysuFodpLTKCToI/AbK4IYOOgyGHZ7xizX
  HYXZdsqX5/zBFXu/NOVrSd/QBYYuCxbqe6tz4wIDAQABAoIBAQCEIRxXrmXIcMlK
  36TfR7h8paUz6Y2+SGew8/d8yvmH4Q2HzeNw41vyUvvsSVbKC0HHIIfzU3C7O+Lt
  9OeiBo2vTKrwNflBv9zPDHHoerlEBLsnNwQ7uEUeTWM9DHdBLwNaLzQApLD6q5iT
  OFW4NfIGpsydIt8R565PiNPDjIcTKwhbVdlsSbI87cLkQ9UuYIMRkvXSD1Q2cg3I
  VsC0SpE4zmfTe7YTZQ5yTxtsoLKPBXrSxhhGuhdayeN7A4YHFYVD39RuQ6/T2w2a
  W/0UaGOk8XWgydDpD5w9wiBdH2I4i6D35IynCcodc5JvmTajzJT+xj6aGjjvMSyq
  q5ZdwJ4JAoGBAOPdZgjbOCf3ONUoiZ5Qw/a4b4xJgMokgqZ5QGBF5GqV1Xsphmk1
  apYmgC7fmab/EOdycrQMS0am2FmtwX1f7gYgJoyWtK4TVkUc5rf+aoWi0ieIsegv
  rjhuiIAc12+vVIbegRgnq8mOI5icrwm6OkwdqHkwTt6VRYdJGEmu67n/AoGBAM3v
  RAd5uIjVwVDLXqaOpvF3pxWfl+cf6PJtAE5y+nbabeTmrw//fJMank3o7qCXkFZR
  F0OJ2tmENwV+LPM8Gy3So8YP2nkOz4bryaGrxQ4eMA+K9+RiACVaKv+tNx/NbyMS
  e9gg504u0cwa60XjM5KUKrmT3RXpY4YIfUPZ1J4dAoGAB6jalDOiSJ2j2G57acn3
  PGTowwN5g9IEXko3IsVWr0qIGZLExOaZxaBXsLutc5KhY9ZSCsFbCm3zWdhgZ7GA
  083i3dj3C970iHA3RToVJJbbj56ltFNd/OGiTwQpLcTsB3iVSFWVDbpsceXacG5F
  JWfd0O0RyaOk6a5IVbm+jMsCgYBglxAOfY4LSE8y6SCM+K3e5iNNZhymgHYPdwbE
  xPMrWgpfab/Evi2dBcgofM+oLU663bAOspMeoP/5qJPGxnNtC7ZbSMZNL6AxBVj+
  ZoW3uHsMXz8kNL8ixecTIxiO5xlwltPVrKExL46hsCKYFhfzcWGUx4DULTLMBCFU
  +M/cFQKBgQC+Ite962yJOnE+bjtSReOrvR9+I+YNGqt7vyRa2nGFxL7ZNIqHss5T
  VjaMgjzVJqqYozNT/74pE/b9UjYyMzO/EhrjUmcwriMMan/vTbYoBMYWvGoy536r
  4n455vizig2c4/sxU5yu9AF9Dv+qNsGCx2e9uUOTDUlHM9NXwxU9rQ==
  -----END RSA PRIVATE KEY-----
  KEY

  SAMPLE_JWT = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJpc3MiOiJBQ0FFIiwiaWF0IjoxMDAwLCJleHAiOjIxNDc0ODM2NDcsImF1ZCI6InByb3Rvbm1haWwuY29tIiwic3ViIjoiMTIzNCIsInUiOnsibiI6ImFiY2RlIiwiZSI6ImFiY2RlQHByb3Rvbm1haWwuY29tIiwicCI6M319.Vpw7paKnUMT3M-wLTd3TKoRIa8iBFc0uyz7GYIO4R-h8C9Dj5_a1OteNJ3xSgDHm6Rge8CxOKqIYkra19cjcJV15YDtsCk3ZVzoKy41wd_OVRanLpAvzVR8AF6fvZWoJDPmoVxF5Ov5CV2f0CmMsJJYUOmRqR4HUY7UO3hfglnBKCMKLNztFGgMCK4F7iDEjuho1boE8XuBOcpntPR7JsqvZy71q4Mg1btTWLTPQryjYp2-Z-tKQQMQ_genUNuqoS0_fXHTjlHAWkRbALE6H1wJGALxDROxlcLimxYZZsHIQS4H0KCPMg7EJPblVYEVvmpFnTzRQPwJGF_f1YNjSkg"

  describe UserJWT do
    it "satisfies round trip property" do
      user_jwt = Generator.user_jwt
      token = user_jwt.encode
      decoded_jwt = UserJWT.decode(token)

      decoded_jwt.id.should eq user_jwt.id
      decoded_jwt.domain.should eq user_jwt.domain
      decoded_jwt.user.permissions.should eq user_jwt.user.permissions
      decoded_jwt.is_admin?.should eq decoded_jwt.is_admin?
      decoded_jwt.is_support?.should eq decoded_jwt.is_support?
    end

    it "encodes" do
      user_jwt = UserJWT.new(**ATTRIBUTES)
      user_jwt.encode(KEY, ALGORITHM).should eq SAMPLE_JWT
    end

    it "decodes" do
      user_jwt = UserJWT.new(**ATTRIBUTES)
      decoded_jwt = UserJWT.decode(SAMPLE_JWT, KEY, ALGORITHM)

      decoded_jwt.id.should eq user_jwt.id
      decoded_jwt.domain.should eq user_jwt.domain
      decoded_jwt.user.permissions.should eq user_jwt.user.permissions
      decoded_jwt.is_admin?.should be_true
      decoded_jwt.is_support?.should be_true
    end
  end
end