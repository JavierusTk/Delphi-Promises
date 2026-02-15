unit TestPromiseTimeout;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.SyncObjs, System.Classes,
  Next.Core.Promises, Next.Core.Promises.Exceptions, Next.Core.Test.Assert;

type
  [TestFixture]
  TTestPromiseTimeout = class
  public
    [Test]
    /// <summary>
    /// Promise resolves before timeout - receives the value.
    /// </summary>
    procedure ResolvesBeforeTimeout;

    [Test]
    /// <summary>
    /// Promise takes too long - rejects with ETimeoutException.
    /// </summary>
    procedure TimesOutRejectsWithTimeout;

    [Test]
    /// <summary>
    /// Timeout in a chain - applies to the specific step.
    /// </summary>
    procedure TimeoutInChain;

    [Test]
    /// <summary>
    /// Timeout with custom message.
    /// </summary>
    procedure TimeoutWithCustomMessage;
  end;

implementation

{ TTestPromiseTimeout }

procedure TTestPromiseTimeout.ResolvesBeforeTimeout;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      Result := 42;
    end)
  .Timeout(5000); // generous timeout

  Assert.Resolves(LPromise);
  Assert.AreEqual(42, LPromise.Await);
end;

procedure TTestPromiseTimeout.TimesOutRejectsWithTimeout;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      Sleep(5000); // Very slow
      Result := 42;
    end)
  .Timeout(100); // Short timeout

  Assert.RejectsWith(LPromise, ETimeoutException);
end;

procedure TTestPromiseTimeout.TimeoutInChain;
var
  LPromise: IPromise<String>;
begin
  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      Result := 42;
    end)
  .Timeout(5000)
  .Op.ThenBy<String>(function(const V: Integer): String
    begin
      Result := IntToStr(V);
    end);

  Assert.Resolves(LPromise);
  Assert.AreEqual('42', LPromise.Await);
end;

procedure TTestPromiseTimeout.TimeoutWithCustomMessage;
var
  LPromise: IPromise<Integer>;
begin
  LPromise := Promise.Resolve<Integer>(function: Integer
    begin
      Sleep(5000);
      Result := 42;
    end)
  .Timeout(100, 'Custom timeout message');

  Assert.RejectsWith(LPromise, ETimeoutException);

  LPromise.InternalWait;
  Assert.AreEqual('Custom timeout message', LPromise.GetFailure.Reason.Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPromiseTimeout);

end.
